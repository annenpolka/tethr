import { expect, test } from "bun:test";
import { createTestRenderer } from "@opentui/core/testing";
import { Palette } from "../src/model.ts";
import { mountPalette } from "../src/view.ts";
import { deferred, UIOnlyHelper } from "./fixtures.ts";
import type { DispatchResult } from "../src/protocol.ts";
import { mkdir } from "node:fs/promises";

test("real native renderer: committed Japanese input, selection, busy, result, empty, resize", async () => {
  expect(process.env.OTUI_NO_NATIVE_RENDER).not.toBe("1");
  expect(process.env.OTUI_NO_NATIVE_RENDER).not.toBe("true");
  const setup = await createTestRenderer({ width: 84, height: 30 });
  const helper = new UIOnlyHelper(), response = deferred<DispatchResult>();
  helper.reply = () => response.promise;
  let view: ReturnType<typeof mountPalette> | undefined;
  const app = new Palette(helper, { onChange: () => view?.sync(), onHide: () => {} });
  const frames: { count: number; cells: number; text: string }[] = [];
  const capture = () => { const stats = setup.getNativeStats(); frames.push({ count: stats.nativeFrameCount, cells: stats.cellsUpdated, text: setup.captureCharFrame() }); };
  setup.renderer.on("frame", capture);
  try {
    view = mountPalette(setup.renderer, app); await app.load(); await setup.renderOnce();
    expect(setup.captureCharFrame()).toContain("同じシェルで続ける");
    const before = setup.getNativeStats().nativeFrameCount;
    const firstFrame = frames.length;
    // Committed characters through bracketed paste; not an OS IME test.
    setup.mockInput.pasteBracketedText("同じ"); await setup.renderOnce();
    expect(app.state.query).toBe("同じ"); expect(app.visible.map(i => i.id)).toEqual(["terminal.step"]);
    expect(setup.captureCharFrame()).toContain("1 件");
    expect(setup.getNativeStats().nativeFrameCount).toBeGreaterThan(before);
    expect(frames.slice(firstFrame).some(frame => frame.cells > 0)).toBe(true);
    view.search.value = "";
    setup.mockInput.pressArrow("down"); await setup.renderOnce();
    expect(app.visible[app.state.selected]?.id).toBe("command.git-status");
    setup.mockInput.pressEnter(); setup.mockInput.pressEnter(); await setup.renderOnce();
    expect(helper.calls).toHaveLength(1); expect(setup.captureCharFrame()).toContain("実行中");
    response.resolve({ protocolVersion: 1, status: "ok", ...helper.calls[0]!, message: "確認完了 / result witness", data: { counter: 7 } });
    await app.settled(); await setup.renderOnce();
    expect(setup.captureCharFrame()).toContain("result witness");
    view.search.value = "nothing matches"; setup.mockInput.pressEnter(); await setup.renderOnce();
    expect(helper.calls).toHaveLength(1); expect(setup.captureCharFrame()).toContain("該当する操作はありません");
    setup.resize(66, 24); await setup.renderOnce();
    expect(setup.captureSpans().cols).toBe(66); expect(setup.captureSpans().rows).toBe(24);
    expect(setup.captureCharFrame()).toContain("result witness");
    // A lone ESC is decoded after the terminal parser's escape ambiguity timer.
    const escaped = new Promise<void>(resolve => setup.renderer.keyInput.once("keypress", () => resolve()));
    setup.mockInput.pressEscape(); await escaped; expect(app.state.hidden).toBe(true);
  } finally {
    await mkdir(".runtime/evidence", { recursive: true });
    await Bun.write(".runtime/evidence/renderer.json", JSON.stringify({
      scope: "real OpenTUI native renderer; UI-only helper substitute; no OS IME or real helper acceptance",
      opentui: "0.5.11", bun: Bun.version, platform: process.platform, arch: process.arch,
      frames, state: app.state, finalFrame: setup.captureCharFrame(), finalSpans: setup.captureSpans(),
    }, null, 2));
    view?.dispose(); setup.renderer.off("frame", capture); setup.renderer.destroy();
  }
});

test("real native renderer shows a helper error, not a success", async () => {
  const setup = await createTestRenderer({ width: 80, height: 28 }), helper = new UIOnlyHelper();
  helper.reply = async () => { throw new Error("helper stdoutが不正です"); };
  let view: ReturnType<typeof mountPalette> | undefined;
  const app = new Palette(helper, { onChange: () => view?.sync() });
  try {
    view = mountPalette(setup.renderer, app); await app.load(); await app.execute(); await setup.renderOnce();
    expect(setup.captureCharFrame()).toContain("エラー"); expect(setup.captureCharFrame()).toContain("helper stdoutが不正です");
  } finally { view?.dispose(); setup.renderer.destroy(); }
});
