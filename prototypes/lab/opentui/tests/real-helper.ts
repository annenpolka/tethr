// Explicit opt-in acceptance: native headless UI + REAL shared helper. No app actions.
import assert from "node:assert/strict";
import { mkdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createTestRenderer } from "@opentui/core/testing";
import { Palette } from "../src/model.ts";
import { parseConfig, ProcessHelper, type DispatchResult } from "../src/protocol.ts";
import { mountPalette } from "../src/view.ts";

const configPath = resolve(process.env.TETHR_LAB_CONFIG ?? "../runtime/config.json");
const config = parseConfig(JSON.parse(await readFile(configPath, "utf8")));
const helper = new ProcessHelper(configPath, config);
const setup = await createTestRenderer({ width: 100, height: 36 });
let view: ReturnType<typeof mountPalette> | undefined;
const app = new Palette(helper, { onChange: () => view?.sync() });
const results: DispatchResult[] = [], frames: string[] = [];
let failure: string | undefined;
try {
  view = mountPalette(setup.renderer, app);
  await app.load();
  assert.equal(app.state.error, null, "real catalog must load");
  const run = async (query: string, actionID: string) => {
    view!.search.value = query;
    assert.equal(app.visible[app.state.selected]?.id, actionID);
    setup.mockInput.pressEnter();
    await app.settled();
    await setup.renderOnce();
    assert.equal(app.state.error, null);
    assert.equal(app.state.result?.status, "ok");
    assert.equal(app.state.result?.actionID, actionID);
    results.push(app.state.result!);
    frames.push(setup.captureCharFrame());
    assert.ok(setup.captureCharFrame().includes("完了"));
    return app.state.result!.data!;
  };
  const first = await run("同じ", "terminal.step");
  const second = await run("同じ", "terminal.step");
  assert.equal(second.shellNonce, first.shellNonce);
  assert.equal(second.shellPID, first.shellPID);
  assert.equal(second.cwd, first.cwd);
  assert.equal(typeof first.counter, "number");
  assert.equal(Number(second.counter), Number(first.counter) + 1, "no other lab action may interleave this pair");
  const command = await run("git status", "command.git-status");
  assert.equal(command.exitCode, 0);
  assert.equal(command.cwd, config.cwd);
  assert.equal(typeof command.stdout, "string");
  assert.ok(setup.getNativeStats().nativeFrameCount > 0);
} catch (error) { failure = String(error); throw error; }
finally {
  await mkdir(".runtime/evidence", { recursive: true });
  await Bun.write(".runtime/evidence/real-helper.json", JSON.stringify({
    scope: "real native OpenTUI renderer + actual helper via Enter; no GUI/IME acceptance",
    configPath, failure: failure ?? null, results, frames, native: setup.getNativeStats(),
  }, null, 2));
  view?.dispose(); setup.renderer.destroy();
}
console.log(JSON.stringify({ status: "passed", terminalCounters: results.slice(0, 2).map(r => r.data?.counter), terminalPID: results[0]?.data?.shellPID, commandExitCode: results[2]?.data?.exitCode, evidence: ".runtime/evidence/real-helper.json" }));
