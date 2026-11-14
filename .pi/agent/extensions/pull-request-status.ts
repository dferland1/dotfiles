import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type Forge = "github" | "gitlab";

type Repository = {
	branch: string;
	forge: Forge;
	reference: string;
	webUrl: string;
};

const STATUS_ID = "pull-request";

function parseRepository(remoteUrl: string, branch: string): Repository | undefined {
	const match = remoteUrl.match(/^(?:https?:\/\/|ssh:\/\/git@|git@)([^/:]+)[/:](.+?)(?:\.git)?$/);
	if (!match) return undefined;

	const [, host, rawPath] = match;
	if (!host || !rawPath) return undefined;
	const path = rawPath.replace(/\.git$/, "");
	const pathSegments = path.split("/");
	if (pathSegments.some((segment) => !segment || segment === "." || segment === "..")) return undefined;
	const webUrl = `https://${host}/${pathSegments.map(encodeURIComponent).join("/")}`;

	if (host === "github.com") {
		if (pathSegments.length !== 2) return undefined;
		return { branch, forge: "github", reference: path, webUrl };
	}

	if (host === "gitlab.com") {
		return { branch, forge: "gitlab", reference: remoteUrl, webUrl };
	}

	return undefined;
}

async function getRepository(
	pi: ExtensionAPI,
	cwd: string,
	signal: AbortSignal,
): Promise<Repository | undefined> {
	const branchResult = await pi.exec("git", ["branch", "--show-current"], { cwd, signal, timeout: 5_000 });
	if (signal.aborted || branchResult.code !== 0) return undefined;

	const branch = branchResult.stdout.trim();
	if (!branch) return undefined;

	let remote = "origin";
	const remoteResult = await pi.exec("git", ["config", "--get", `branch.${branch}.remote`], {
		cwd,
		signal,
		timeout: 5_000,
	});
	if (signal.aborted) return undefined;
	if (remoteResult.code === 0 && remoteResult.stdout.trim() !== ".") {
		remote = remoteResult.stdout.trim();
	}

	const urlResult = await pi.exec("git", ["remote", "get-url", remote], { cwd, signal, timeout: 5_000 });
	if (signal.aborted || urlResult.code !== 0) return undefined;

	return parseRepository(urlResult.stdout.trim(), branch);
}

async function getRequestNumber(
	pi: ExtensionAPI,
	cwd: string,
	repository: Repository,
	signal: AbortSignal,
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
					{ cwd, signal, timeout: 10_000 },
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
					{ cwd, signal, timeout: 10_000 },
				);

	if (result.code !== 0) return undefined;

	const number = result.stdout.trim();
	return /^\d+$/.test(number) ? number : undefined;
}

export default function (pi: ExtensionAPI): void {
	let refreshController: AbortController | undefined;

	const refresh = async (ctx: ExtensionContext): Promise<void> => {
		refreshController?.abort();
		refreshController = new AbortController();
		const { signal } = refreshController;
		const repository = await getRepository(pi, ctx.cwd, signal);
		if (signal.aborted) return;
		const number = repository ? await getRequestNumber(pi, ctx.cwd, repository, signal) : undefined;
		if (signal.aborted) return;

		if (!repository || !number) {
			ctx.ui.setStatus(STATUS_ID, undefined);
			return;
		}

		const label = repository.forge === "github" ? `PR #${number}` : `MR !${number}`;
		const requestPath = repository.forge === "github" ? "pull" : "-/merge_requests";
		const url = `${repository.webUrl}/${requestPath}/${number}`;
		const link = `\u001b]8;;${url}\u001b\\${ctx.ui.theme.fg("accent", label)}\u001b]8;;\u001b\\`;
		ctx.ui.setStatus(STATUS_ID, link);
	};

	pi.on("session_start", (_event, ctx) => {
		return refresh(ctx);
	});

	pi.on("agent_settled", (_event, ctx) => {
		return refresh(ctx);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		refreshController?.abort();
		ctx.ui.setStatus(STATUS_ID, undefined);
	});
}
