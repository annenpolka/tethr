import { describe, expect, test } from "bun:test";
import { Window } from "happy-dom";
import { CompositionGuard, filterItems, Launcher, type Bridge, type Item, type Reply } from "../src/model";
import { mount } from "../src/ui";

const items: Item[] = [
  { id: "terminal.step", title: "同じシェルで続ける", subtitle: "tmux の状態", keywords: "terminal shell ターミナル", kind: "terminal" },
  { id: "command.git-status", title: "変更状況を見る", subtitle: "Git status", keywords: "git changes 変更", kind: "command" },
  { id: "app.fixture-b", title: "受信アプリ B", subtitle: "run-or-raise", keywords: "Application アプリ", kind: "application" },
];
const catalog: Reply = { protocolVersion: 1, status: "ok", items };
const done = (actionID: string, requestID: string): Reply => ({ protocolVersion: 1, status: "ok", actionID, requestID, message: "完了", data: { counter: 1 } });
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
function setup(overrides: Partial<Bridge> = {}) {
  const calls: string[] = [];
  const bridge: Bridge = {
    catalog: async () => catalog,
    hide: async () => { calls.push("hide"); },
    dispatch: async (action, request) => { calls.push(action); return done(action, request); },
    ...overrides,
  };
  const model = new Launcher(bridge, () => {}, () => "request-test");
  return { model, calls, bridge };
}

describe("component logic with substitute bridge (not native E2E)", () => {
  test("case-folded all-token search preserves catalog order", () => {
    expect(filterItems(items, "GIT  status").map(i => i.id)).toEqual(["command.git-status"]);
    expect(filterItems(items, "tmux ターミナル").map(i => i.id)).toEqual(["terminal.step"]);
    expect(filterItems(items, "git ターミナル")).toEqual([]);
    expect(filterItems(items, "  ")).toEqual(items);
  });
  test("selection wraps and empty results cannot execute", async () => {
    const { model, calls } = setup(); await model.load();
    model.move(-1); expect(model.selected).toBe(2); model.move(1); expect(model.selected).toBe(0);
    model.search("missing"); model.move(1); await model.execute();
    expect(model.selected).toBe(0); expect(calls).toEqual([]);
  });
  test("busy suppresses duplicate dispatch; result remains attributed to original action", async () => {
    const pending = deferred<Reply>(); let count = 0;
    const { model } = setup({ dispatch: async () => { count++; return pending.promise; } }); await model.load();
    const first = model.execute(); model.search("git"); await model.execute();
    expect(count).toBe(1); expect(model.busy).toBe(true);
    pending.resolve(done("terminal.step", "request-test")); await first;
    expect(model.busy).toBe(false); expect(model.output).toContain("同じシェルで続ける"); expect(model.output).toContain('"counter": 1');
  });
  test("application hide completes before dispatch and completion does not show or focus", async () => {
    const { model, calls } = setup(); await model.load(); model.search("application"); await model.execute();
    expect(calls).toEqual(["hide", "app.fixture-b"]); expect(model.error).toBe(false);
  });
  test("failed hide prevents app dispatch and leaves readable error", async () => {
    const { model, calls } = setup({ hide: async () => { throw new Error("hide refused"); } });
    await model.load(); model.search("application"); await model.execute();
    expect(calls).toEqual([]); expect(model.error).toBe(true); expect(model.output).toContain("hide refused");
  });
  test("helper error and transport rejection are errors, never completion", async () => {
    const { model } = setup({ dispatch: async (actionID, requestID) => ({ protocolVersion: 1, status: "error", actionID, requestID, message: "受信なし", errorCode: "unavailable" }) });
    await model.load(); await model.execute(); expect(model.error).toBe(true); expect(model.output).toContain("失敗 (unavailable)"); expect(model.output).toContain("受信なし");
    model.bridge.dispatch = async () => { throw new Error("process failed"); };
    await model.execute(); expect(model.error).toBe(true); expect(model.output).toContain("process failed"); expect(model.busy).toBe(false);
  });
  test("uncorrelated reply is rejected rather than displayed as success", async () => {
    const { model } = setup({ dispatch: async () => done("app.fixture-b", "other-request") }); await model.load(); await model.execute();
    expect(model.error).toBe(true); expect(model.output).toContain("到達状態は不明");
  });
  test("catalog failure is visible and leaves no selectable action", async () => {
    const { model, calls } = setup({ catalog: async () => { throw new Error("config missing"); } }); await model.load(); await model.execute();
    expect(model.visible).toEqual([]); expect(model.output).toContain("config missing"); expect(model.error).toBe(true); expect(calls).toEqual([]);
  });
  test("older catalog response cannot replace a newer load", async () => {
    const old = deferred<Reply>(); let call = 0;
    const { model } = setup({ catalog: async () => ++call === 1 ? old.promise : { ...catalog, items: [items[1]] } });
    const first = model.load(); await model.load(); old.resolve(catalog); await first;
    expect(model.items.map(i => i.id)).toEqual(["command.git-status"]);
  });
  test("IME confirmation, Safari keyCode 229, and composition-end-before-keyup stay blocked", () => {
    const guard = new CompositionGuard(); const key = { isComposing: false, keyCode: 13 };
    guard.start(); expect(guard.blocked(key)).toBe(true); guard.end(); expect(guard.blocked(key)).toBe(true);
    guard.release(); expect(guard.blocked(key)).toBe(false);
    expect(guard.blocked({ isComposing: true, keyCode: 13 })).toBe(true);
    expect(guard.blocked({ isComposing: false, keyCode: 229 })).toBe(true);
  });
});

test("real UI event handlers in substitute DOM: composition does not execute, next Enter does, error is rendered", async () => {
  const window = new Window(); const root = window.document.createElement("main"); window.document.body.append(root);
  let calls = 0;
  const { bridge } = setup({ dispatch: async (actionID, requestID) => { calls++; return { protocolVersion: 1, status: "error", actionID, requestID, message: "fixture rejection", errorCode: "test" }; } });
  const model = mount(root as unknown as HTMLElement, bridge); await new Promise(resolve => setTimeout(resolve, 0));
  const input = root.querySelector("input")!;
  input.dispatchEvent(new window.CompositionEvent("compositionstart"));
  input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  input.dispatchEvent(new window.CompositionEvent("compositionend"));
  input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  expect(calls).toBe(0);
  input.dispatchEvent(new window.KeyboardEvent("keyup", { key: "Enter", bubbles: true }));
  input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  await new Promise(resolve => setTimeout(resolve, 0));
  expect(calls).toBe(1); expect(root.querySelector("#output")!.textContent).toContain("fixture rejection"); expect(model.error).toBe(true);
  input.value = "does not exist"; input.dispatchEvent(new window.Event("input"));
  input.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  expect(calls).toBe(1); expect(root.querySelector("#results")!.textContent).toContain("一致する操作はありません");
  await window.happyDOM.close();
});
