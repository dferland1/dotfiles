import { describe, expect, test } from "bun:test";
import contextUsage from "../extensions/context-usage.ts";

function setup() {
	const hooks = new Map<string, (event: unknown, ctx: any) => void>();
	const values: string[] = [];
	contextUsage({
		on: (event: string, handler: any) => hooks.set(event, handler),
		events: {
			emit: (event: string, payload: { widgetId: string; value: string }) => {
				expect(event).toBe("pi-footer:update-widget");
				expect(payload.widgetId).toBe("context-usage");
				values.push(payload.value);
			},
		},
	} as any);
	return { hooks, values };
}

describe("context usage footer", () => {
	for (const [usage, expected] of [
		[{ tokens: 24_100, contextWindow: 500_000 }, "24.1k (4.8%)"],
		[{ tokens: 0, contextWindow: 500_000 }, "0 (0.0%)"],
		[{ tokens: 500, contextWindow: 500_000 }, "500 (0.1%)"],
		[{ tokens: 1_200_000, contextWindow: 2_000_000 }, "1.2m (60.0%)"],
		[{ tokens: 24_100, contextWindow: 0 }, "24.1k (?)"],
		[{ tokens: null, contextWindow: 500_000 }, "?"],
		[undefined, "?"],
	] as const) {
		test(`formats ${JSON.stringify(usage)}`, () => {
			const app = setup();
			app.hooks.get("session_start")!({}, { mode: "tui", getContextUsage: () => usage });
			expect(app.values).toEqual([expected]);
		});
	}

	test("refreshes after usage, session, compaction, and model changes", () => {
		const app = setup();
		for (const event of ["session_start", "session_tree", "session_compact", "model_select", "message_end", "turn_end", "agent_settled"]) {
			app.hooks.get(event)!({}, {
				mode: "tui",
				getContextUsage: () => ({ tokens: 24_100, contextWindow: 500_000 }),
			});
		}
		expect(app.values).toEqual(Array(7).fill("24.1k (4.8%)"));
	});

	test("does not publish outside TUI mode", () => {
		const app = setup();
		for (const mode of ["rpc", "json", "print"]) {
			app.hooks.get("session_start")!({}, { mode });
		}
		expect(app.values).toEqual([]);
	});
});
