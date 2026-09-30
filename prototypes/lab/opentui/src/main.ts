import { createCliRenderer } from "@opentui/core";
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import { mkdir, rename, readFile } from "node:fs/promises";
import { resolve, dirname, join } from "node:path";
import { Palette, type SavedResult } from "./model.ts";
import { parseConfig, parseDispatch, ProcessHelper } from "./protocol.ts";
import { mountPalette } from "./view.ts";

async function main(): Promise<void> {
  const rawPath = process.env.TETHR_LAB_CONFIG;
  if (!rawPath) throw new Error("TETHR_LAB_CONFIGに共通configの絶対パスを設定してください。");
  const configPath = resolve(rawPath);
  const config = parseConfig(JSON.parse(await readFile(configPath, "utf8")));
  const statePath = join(import.meta.dir, "../.runtime", `${createHash("sha256").update(JSON.stringify([configPath, config])).digest("hex").slice(0, 16)}.json`);
  const save = async (state: SavedResult): Promise<void> => {
    await mkdir(dirname(statePath), { recursive: true });
    const temporary = `${statePath}.${process.pid}.tmp`;
    await Bun.write(temporary, JSON.stringify(state));
    await rename(temporary, statePath);
  };
  const renderer = await createCliRenderer({ exitOnCtrlC: false, exitSignals: [], screenMode: "alternate-screen", consoleMode: "disabled", useMouse: true });
  renderer.setTerminalTitle("tethr · OpenTUI");
  let view: ReturnType<typeof mountPalette> | undefined;
  let finish!: () => void;
  const done = new Promise<void>(resolve => { finish = resolve; });
  const palette = new Palette(new ProcessHelper(configPath, config), {
    save,
    onChange: state => { if (!state.hidden) view?.sync(); if (state.hidden && !state.busy && !state.loading) finish(); },
    onHide: () => { view?.dispose(); renderer.destroy(); },
  });
  const hide = () => palette.hide();
  process.on("SIGINT", hide);
  process.on("SIGTERM", hide);
  try {
    view = mountPalette(renderer, palette);
    try {
      const saved: unknown = JSON.parse(await readFile(statePath, "utf8"));
      if (typeof saved === "object" && saved !== null && "kind" in saved) {
        const s = saved as SavedResult;
        if (s.kind === "result") palette.restore({ kind: "result", result: parseDispatch(s.result, s.result.actionID, s.result.requestID) });
        else if (s.kind === "error" && typeof s.message === "string") palette.restore(s);
        else if (s.kind === "pending" && typeof s.actionID === "string") palette.restore(s);
      }
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") palette.restore({ kind: "error", message: `前回結果の読み込みに失敗: ${String(error)}` });
    }
    await palette.load();
    await done;
    await palette.settled();
  } finally {
    EventEmitter.prototype.removeListener.call(process, "SIGINT", hide);
    EventEmitter.prototype.removeListener.call(process, "SIGTERM", hide);
    view?.dispose();
    if (!palette.state.hidden) renderer.destroy();
  }
}

if (import.meta.main) {
  main().catch(error => { console.error(`tethr OpenTUI: ${error instanceof Error ? error.message : String(error)}`); process.exitCode = 1; });
}
