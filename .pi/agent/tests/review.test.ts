import { afterAll, afterEach, beforeEach, describe, expect, mock, test } from "bun:test";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const agentDir = await mkdtemp(join(tmpdir(), "pi-review-state-test-"));
mock.module("@earendil-works/pi-coding-agent", () => ({
	getAgentDir: () => agentDir,
	BorderedLoader: class {
		onAbort?: () => void;
	},
}));
const { default: review } = await import("../extensions/review.ts");

async function command(cwd: string, args: string[]) {
	const child = Bun.spawn(args, { cwd, stdout: "pipe", stderr: "pipe" });
	const [stdout, stderr, code] = await Promise.all([
		new Response(child.stdout).text(),
		new Response(child.stderr).text(),
		child.exited,
	]);
	return { stdout, stderr, code, killed: false, truncated: false };
}

let cwd: string;
beforeEach(async () => {
	cwd = await mkdtemp(join(tmpdir(), "pi-review-repo-test-"));
	await command(cwd, ["git", "init", "--initial-branch=main"]);
	await command(cwd, ["git", "config", "user.email", "test@example.com"]);
	await command(cwd, ["git", "config", "user.name", "Test"]);
	await writeFile(join(cwd, "tracked.ts"), "original\n");
	await command(cwd, ["git", "add", "."]);
	await command(cwd, ["git", "commit", "-m", "initial"]);
	await rm(join(agentDir, "review-model.json"), { force: true });
});
afterEach(() => rm(cwd, { recursive: true, force: true }));
afterAll(() => rm(agentDir, { recursive: true, force: true }));

function setup(options: {
	select?: string | null;
	cancel?: boolean;
	mode?: string;
	idle?: boolean;
	scoped?: boolean;
	child?: { code: number; stdout: string; stderr: string; killed?: boolean; truncated?: boolean };
} = {}) {
	let handler: (args: string, ctx: any) => Promise<void>;
	const hooks = new Map<string, () => void>();
	const messages: any[] = [];
	const notifications: string[] = [];
	const menus: string[][] = [];
	const calls: { args: string[]; options: any; snapshot: string; path: string }[] = [];
	const models = [
		{ provider: "test", id: "coder" },
		{ provider: "other", id: "reviewer" },
	];
	const pi = {
		on: (name: string, fn: () => void) => hooks.set(name, fn),
		registerCommand: (name: string, definition: any) => {
			expect(name).toBe("review");
			handler = definition.handler;
		},
		sendMessage: (message: any) => messages.push(message),
		exec: async (name: string, args: string[], execOptions: any) => {
			if (name === "git") return command(execOptions.cwd, [name, ...args]);
			expect(name).toBe("pi");
			const path = JSON.parse(args.at(-1)!.match(/^Read (".*?") for/)![1]);
			calls.push({ args, options: execOptions, snapshot: await readFile(path, "utf8"), path });
			return options.child ?? { code: 0, stdout: "No actionable findings.", stderr: "" };
		},
	};
	const ctx = {
		cwd,
		mode: options.mode ?? "tui",
		model: models[0],
		isIdle: () => options.idle ?? true,
		isProjectTrusted: () => true,
		scopedModels: options.scoped ? [{ model: models[1] }] : [],
		modelRegistry: { getAvailable: () => models },
		ui: {
			notify: (message: string) => notifications.push(message),
			select: async (_title: string, choices: string[]) => {
				menus.push(choices);
				return options.select === null ? undefined : (options.select ?? choices[0]);
			},
			custom: (factory: any) => new Promise((resolve) => {
				const loader = factory({}, {}, {}, resolve);
				if (options.cancel) loader.onAbort();
			}),
		},
	};
	review(pi as any);
	return { run: (args = "") => handler(args, ctx), messages, notifications, menus, calls, ctx, hooks };
}

async function change() {
	await writeFile(join(cwd, "tracked.ts"), "changed\n");
}

describe("/review", () => {
	test("collects staged, unstaged and untracked changes without changing the coding model", async () => {
		await change();
		await command(cwd, ["git", "add", "tracked.ts"]);
		await writeFile(join(cwd, "tracked.ts"), "another change\n");
		await writeFile(join(cwd, "new file.ts"), "new\n");
		const app = setup({ select: "other/reviewer" });
		await app.run();
		expect(app.calls).toHaveLength(1);
		expect(app.calls[0].snapshot).toContain("## Staged changes");
		expect(app.calls[0].snapshot).toContain("## Unstaged changes");
		expect(app.calls[0].snapshot).toContain('"new file.ts"');
		expect(app.ctx.model.id).toBe("coder");
		expect(app.messages[0].content).toContain("other/reviewer");
		expect(app.messages[0].content).toContain("No actionable findings.");
		await expect(readFile(app.calls[0].path)).rejects.toMatchObject({ code: "ENOENT" });
	});

	test("child has fresh context, only read/search tools and disabled extensions/MCP", async () => {
		await change();
		const app = setup();
		await app.run();
		const { args, options } = app.calls[0];
		for (const flag of ["--print", "--no-session", "--no-extensions", "--no-mcp", "--no-skills", "--no-prompt-templates"]) {
			expect(args).toContain(flag);
		}
		expect(args[args.indexOf("--tools") + 1]).toBe("read,grep,find,ls");
		expect(args).not.toContain("--continue");
		expect(args).not.toContain("--session");
		expect(options.timeout).toBe(600_000);
		expect(await readFile(join(cwd, "tracked.ts"), "utf8")).toBe("changed\n");
	});

	test("remembers the selected review model across extension instances", async () => {
		await change();
		await setup({ select: "test/coder" }).run();
		const app = setup();
		await app.run();
		expect(app.menus[0][0]).toBe("test/coder");
		expect(JSON.parse(await readFile(join(agentDir, "review-model.json"), "utf8"))).toBe("test/coder");
	});

	test("uses the scoped model list", async () => {
		await change();
		const app = setup({ scoped: true });
		await app.run();
		expect(app.menus[0]).toEqual(["other/reviewer"]);
	});

	test("does not launch a reviewer when the model picker is cancelled", async () => {
		await change();
		const app = setup({ select: null });
		await app.run();
		expect(app.calls).toHaveLength(0);
		expect(app.messages).toHaveLength(0);
	});

	test("skips clean repositories without opening the model picker", async () => {
		const app = setup();
		await app.run();
		expect(app.calls).toHaveLength(0);
		expect(app.menus).toHaveLength(0);
		expect(app.notifications[0]).toContain("No changes");
	});

	test("reviews committed branch changes against an explicit base", async () => {
		await command(cwd, ["git", "switch", "-c", "feature"]);
		await change();
		await command(cwd, ["git", "commit", "-am", "feature"]);
		const app = setup();
		await app.run("main");
		expect(app.calls[0].snapshot).toContain("Changes since merge base with main");
		expect(app.calls[0].snapshot).toContain("+changed");
	});

	test("supports staged additions before the first commit", async () => {
		await rm(join(cwd, ".git"), { recursive: true });
		await command(cwd, ["git", "init"]);
		await command(cwd, ["git", "add", "tracked.ts"]);
		const app = setup();
		await app.run();
		expect(app.calls[0].snapshot).toContain("new file mode");
	});

	test("rejects invalid or option-shaped refs instead of executing them", async () => {
		const app = setup();
		await app.run("--output=/tmp/pi-review-should-not-exist");
		expect(app.calls).toHaveLength(0);
		expect(app.notifications[0]).toContain("Review failed");
	});

	test("surfaces provider failures instead of reporting a successful review", async () => {
		await change();
		const app = setup({ child: { code: 1, stdout: "partial", stderr: "provider unavailable" } });
		await app.run();
		expect(app.messages).toHaveLength(0);
		expect(app.notifications.join("\n")).toContain("provider unavailable");
	});

	test("does not present timed-out or truncated reports as completed reviews", async () => {
		await change();
		const app = setup({ child: { code: 0, stdout: "partial", stderr: "", truncated: true } });
		await app.run();
		expect(app.messages).toHaveLength(0);
		expect(app.notifications.join("\n")).toContain("10-minute limit");
	});

	test("Escape aborts the child without reporting findings", async () => {
		await change();
		const app = setup({ cancel: true });
		await app.run();
		expect(app.calls[0].options.signal.aborted).toBe(true);
		expect(app.messages).toHaveLength(0);
		expect(app.notifications).toContain("Review cancelled");
	});

	test("refuses to review while the coding agent is busy", async () => {
		const app = setup({ idle: false });
		await app.run();
		expect(app.calls).toHaveLength(0);
		expect(app.notifications[0]).toContain("Wait for");
	});
});
