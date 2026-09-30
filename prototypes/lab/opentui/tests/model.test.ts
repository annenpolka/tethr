import { describe, expect, test } from "bun:test";
import { Palette, filterCatalog, resultText, type SavedResult } from "../src/model.ts";
import { catalog, deferred, UIOnlyHelper } from "./fixtures.ts";
import type { DispatchResult } from "../src/protocol.ts";

describe("UI state only (helper substitute)", () => {
  test("token AND matching across title/subtitle/keywords preserves catalog order", () => {
    expect(filterCatalog(catalog, "  TMUX  続き ").map(i => i.id)).toEqual(["terminal.step"]);
    expect(filterCatalog(catalog, "git status").map(i => i.id)).toEqual(["command.git-status"]);
    expect(filterCatalog(catalog, "")).toEqual(catalog);
    expect(filterCatalog(catalog, "tmux git")).toEqual([]);
  });
  test("empty, composing and busy do not dispatch; selected identity is frozen", async () => {
    const helper = new UIOnlyHelper(), response = deferred<DispatchResult>();
    helper.reply = () => response.promise;
    const app = new Palette(helper, { requestID: () => "request-1" });
    await app.load();
    app.setQuery("no match"); await app.execute(); expect(helper.calls).toHaveLength(0);
    app.setQuery(""); app.move(1); app.setComposing(true); await app.execute(); expect(helper.calls).toHaveLength(0);
    app.setComposing(false);
    const done = app.execute(); await app.execute();
    expect(helper.calls).toEqual([{ actionID: "command.git-status", requestID: "request-1" }]);
    app.setQuery("app");
    response.resolve({ protocolVersion: 1, status: "ok", actionID: "command.git-status", requestID: "request-1", message: "git完了" });
    await done; expect(resultText(app.state)).toContain("git完了"); expect(app.state.busy).toBe(false);
  });
  test("app hides before dispatch, waits for result and saves error for reopen", async () => {
    const order: string[] = [], saves: SavedResult[] = [], helper = new UIOnlyHelper();
    helper.reply = async (actionID, requestID) => { order.push("dispatch"); return { protocolVersion: 1, status: "error", actionID, requestID, message: "起動できません", errorCode: "APP_FAILED" }; };
    const app = new Palette(helper, { onHide: () => order.push("hide"), save: async value => { saves.push(value); } });
    await app.load(); app.setQuery("app"); await app.execute();
    expect(order).toEqual(["hide", "dispatch"]); expect(app.state.hidden).toBe(true);
    const reopened = new Palette(helper); reopened.restore(saves.at(-1)!);
    expect(resultText(reopened.state)).toContain("起動できません"); expect(resultText(reopened.state)).toContain("エラー");
  });
  test("Escape hide does not cancel an already dispatched operation", async () => {
    const helper = new UIOnlyHelper(), response = deferred<DispatchResult>(); helper.reply = () => response.promise;
    const app = new Palette(helper); await app.load(); const done = app.execute(); app.hide(); await app.execute();
    expect(helper.calls).toHaveLength(1); expect(app.state.busy).toBe(true);
    response.resolve({ protocolVersion: 1, status: "ok", ...helper.calls[0]!, message: "hidden完了" });
    await done; expect(resultText(app.state)).toContain("hidden完了");
  });
});
