import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Forge = "github" | "gitlab";

type Repository = {
	branch: string;
	forge: Forge;
	reference: string;
};

const STATUS_ID = "pull-request";

function parseRepository(remoteUrl: string, branch: string): Repository | undefined {
	const match = remoteUrl.match(/^(?:https?:\/\/|ssh:\/\/git@|git@)([^/:]+)[/:](.+?)(?:\.git)?$/);
	if (!match) return undefined;

	const [, host, rawPath] = match;
	if (!host || !rawPath) return undefined;
	const path = rawPath.replace(/\.git$/, "");

	if (host === "github.com") {
		return { branch, forge: "github", reference: path };
	}

	if (host === "gitlab.com") {
		return { branch, forge: "gitlab", reference: remoteUrl };
	}

	return undefined;
}

async function getRepository(pi: ExtensionAPI, cwd: string): Promise<Repository | undefined> {
	const branchResult = await pi.exec("git", ["branch", "--show-current"], { cwd, timeout: 5_000 });
	if (branchResult.code !== 0) return undefined;

	const branch = branchResult.stdout.trim();
	if (!branch) return undefined;

	let remote = "origin";
	const remoteResult = await pi.exec("git", ["config", "--get", `branch.${branch}.remote`], {
		cwd,
		timeout: 5_000,
	});
	if (remoteResult.code === 0 && remoteResult.stdout.trim() !== ".") {
		remote = remoteResult.stdout.trim();
	}

	const urlResult = await pi.exec("git", ["remote", "get-url", remote], { cwd, timeout: 5_000 });
	if (urlResult.code !== 0) return undefined;

	return parseRepository(urlResult.stdout.trim(), branch);
}

async function getRequestNumber(
	pi: ExtensionAPI,
	cwd: string,
	repository: Repository,
): Promise<string | undefined> {
	const result =
		repository.forge === "github"
			? await pi.exec(
					"gh",
					[
						"pr",
						"view",
						repository.branch,
						"--repo",
						repository.reference,
						"--json",
						"number",
						"--jq",
						".number",
					],
					{ cwd, timeout: 10_000 },
				)
			: await pi.exec(
					"glab",
					[
						"mr",
						"view",
						repository.branch,
						"--repo",
						repository.reference,
						"--output",
						"json",
						"--jq",
						".iid",
					],
					{ cwd, timeout: 10_000 },
				);

	if (result.code !== 0) return undefined;

	const number = result.stdout.trim();
	return /^\d+$/.test(number) ? number : undefined;
}

export default function (pi: ExtensionAPI): void {
	let refreshVersion = 0;

	const refresh = async (ctx: ExtensionContext): Promise<void> => {
		const version = ++refreshVersion;
		const repository = await getRepository(pi, ctx.cwd);
		const number = repository ? await getRequestNumber(pi, ctx.cwd, repository) : undefined;
		if (version !== refreshVersion) return;

		if (!repository || !number) {
			ctx.ui.setStatus(STATUS_ID, undefined);
			return;
		}

		const label = repository.forge === "github" ? `PR #${number}` : `MR !${number}`;
		ctx.ui.setStatus(STATUS_ID, ctx.ui.theme.fg("accent", label));
	};

	pi.on("session_start", (_event, ctx) => {
		void refresh(ctx);
	});

	pi.on("agent_settled", (_event, ctx) => {
		void refresh(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		refreshVersion++;
		ctx.ui.setStatus(STATUS_ID, undefined);
	});
}
