import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI): void {
	const refresh = (_event: unknown, ctx: ExtensionContext): void => {
		if (ctx.mode !== "tui") return;
		const usage = ctx.getContextUsage();
		let value = "?";
		if (usage?.tokens != null) {
			const tokens = usage.tokens;
			const count = tokens >= 1_000_000
				? `${(tokens / 1_000_000).toFixed(1)}m`
				: tokens >= 1_000 ? `${(tokens / 1_000).toFixed(1)}k` : `${tokens}`;
			const percent = usage.contextWindow > 0
				? `${((tokens / usage.contextWindow) * 100).toFixed(1)}%`
				: "?";
			value = `${count} (${percent})`;
		}
		pi.events.emit("pi-footer:update-widget", { widgetId: "context-usage", value });
	};

	pi.on("session_start", refresh);
	pi.on("session_tree", refresh);
	pi.on("session_compact", refresh);
	pi.on("model_select", refresh);
	pi.on("message_end", refresh);
	pi.on("turn_end", refresh);
	pi.on("agent_settled", refresh);
}
