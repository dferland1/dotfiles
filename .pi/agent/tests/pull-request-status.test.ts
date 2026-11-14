import { describe, expect, test } from "bun:test";
import pullRequestStatus from "../extensions/pull-request-status.ts";

const result = (stdout: string, code = 0) => ({ stdout, stderr: "", code, killed: false, truncated: false });

function setup(options: { pauseAt?: number; forge?: "github" | "gitlab"; failAt?: number } = {}) {
	const hooks = new Map<string, (event: unknown, ctx: any) => void | Promise<void>>();
	const calls: { command: string; args: string[]; signal: AbortSignal }[] = [];
	const statuses: (string | undefined)[] = [];
	const outputs = ["feature", "origin", `git@${options.forge ?? "github"}.com:owner/repo.git`, "42"];
	let release!: () => void;
	let paused!: () => void;
	const waiting = new Promise<void>((resolve) => { paused = resolve; });
	const gate = new Promise<void>((resolve) => { release = resolve; });
	const pi = {
		on: (event: string, handler: any) => hooks.set(event, handler),
		exec: async (command: string, args: string[], execOptions: { signal: AbortSignal }) => {
			const index = calls.length;
			calls.push({ command, args, signal: execOptions.signal });
			if (index === options.pauseAt) {
				paused();
				await gate;
			}
			if (index === options.failAt) throw new Error("exec failed");
			return result(outputs[index % outputs.length]);
		},
	};
	const ctx = {
		cwd: "/repo",
		ui: {
			setStatus: (id: string, value: string | undefined) => {
				expect(id).toBe("pull-request");
				statuses.push(value);
			},
			theme: { fg: (_color: string, text: string) => text },
		},
	};
	pullRequestStatus(pi as any);
	return { calls, statuses, waiting, release, emit: (event: string) => hooks.get(event)!({}, ctx) };
}

describe("pull request status lifecycle", () => {
	for (const forge of ["github", "gitlab"] as const) {
		test(`renders ${forge} request links`, async () => {
			const app = setup({ forge });
			await app.emit("session_start");
			expect(app.calls).toHaveLength(4);
			expect(app.calls[3].command).toBe(forge === "github" ? "gh" : "glab");
			expect(app.statuses[0]).toContain(forge === "github" ? "PR #42" : "MR !42");
			expect(app.statuses[0]).toContain(`https://${forge}.com/owner/repo/${forge === "github" ? "pull" : "-/merge_requests"}/42`);
		});
	}

	for (const event of ["session_start", "agent_settled"]) {
		for (const pauseAt of [0, 1, 2, 3]) {
			test(`shutdown during ${event} command ${pauseAt + 1} stops the refresh`, async () => {
				const app = setup({ pauseAt });
				const refresh = app.emit(event);
				await app.waiting;
				await app.emit("session_shutdown");
				expect(app.calls[pauseAt].signal.aborted).toBe(true);
				app.release();
				await refresh;
				expect(app.calls).toHaveLength(pauseAt + 1);
				expect(app.statuses).toEqual([undefined]);
			});
		}
	}

	test("a newer refresh cancels the older one without overwriting its status", async () => {
		const app = setup({ pauseAt: 3 });
		const first = app.emit("session_start");
		await app.waiting;
		await app.emit("agent_settled");
		expect(app.calls[3].signal.aborted).toBe(true);
		expect(app.statuses).toHaveLength(1);
		app.release();
		await first;
		expect(app.statuses).toHaveLength(1);
	});

	test("returns unexpected failures to Pi's event dispatcher", async () => {
		const app = setup({ failAt: 0 });
		await expect(app.emit("session_start")).rejects.toThrow("exec failed");
	});
});
