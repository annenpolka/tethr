import { BoxRenderable, InputRenderable, InputRenderableEvents, SelectRenderable, ScrollBoxRenderable, TextRenderable, type CliRenderer, type KeyEvent } from "@opentui/core";
import { Palette, resultText } from "./model.ts";

export function mountPalette(renderer: CliRenderer, palette: Palette) {
  const root = new BoxRenderable(renderer, { id: "tethr-root", width: "100%", height: "100%", flexDirection: "column", padding: 1, gap: 1, backgroundColor: "#101723" });
  const title = new TextRenderable(renderer, { id: "title", content: "tethr / OpenTUI     terminal lab", fg: "#74d9c4", height: 1 });
  const search = new InputRenderable(renderer, { id: "search", width: "100%", placeholder: "用事を検索…  terminal / git / app", focusedBackgroundColor: "#243047", textColor: "#f1f5fb", cursorColor: "#74d9c4", maxLength: 1000 });
  const count = new TextRenderable(renderer, { id: "count", content: "読み込み中…", height: 1, fg: "#9daec5" });
  const menu = new SelectRenderable(renderer, { id: "results", options: [], width: "100%", height: 6, showDescription: true, showScrollIndicator: true, selectedBackgroundColor: "#284856", selectedTextColor: "#ffffff", descriptionColor: "#9daec5", selectedDescriptionColor: "#d3e7e9", textColor: "#c3cedf" });
  const output = new ScrollBoxRenderable(renderer, { id: "output-scroll", width: "100%", flexGrow: 1, minHeight: 3, scrollY: true, scrollX: false, border: true, borderColor: "#3a5068", title: "結果", contentOptions: { flexDirection: "column", padding: 1 } });
  const result = new TextRenderable(renderer, { id: "output", width: "100%", content: "", fg: "#d6dfed", wrapMode: "word", selectable: true });
  const hint = new TextRenderable(renderer, { id: "hint", content: "↑↓ 選択  Enter 実行  PgUp/PgDn 結果  Esc 閉じる", height: 1, fg: "#9daec5" });
  output.add(result);
  for (const child of [title, search, count, menu, output, hint]) root.add(child);
  renderer.root.add(root);
  search.focus();

  const sync = () => {
    if (palette.state.hidden) return;
    const state = palette.state, visible = palette.visible;
    count.content = state.loading ? "読み込み中…" : visible.length === 0 ? "該当する操作はありません" : `${visible.length} 件${state.busy ? " · 実行中" : ""}`;
    menu.options = visible.map(item => ({ name: item.title, description: item.subtitle, value: item.id }));
    if (visible.length > 0) menu.setSelectedIndex(state.selected);
    result.content = resultText(state);
    result.fg = state.error || state.result?.status === "error" ? "#ffacb4" : "#d6dfed";
    renderer.requestRender();
  };
  const onInput = (value: string) => palette.setQuery(value);
  const onKey = (key: KeyEvent) => {
    if (key.name === "escape" || (key.ctrl && key.name === "c")) { key.preventDefault(); palette.hide(); }
    else if (key.name === "up" || key.name === "down") { key.preventDefault(); palette.move(key.name === "up" ? -1 : 1); }
    else if (key.name === "return" || key.name === "enter") { key.preventDefault(); if (!key.repeated) void palette.execute(); }
    else if (key.name === "pageup" || key.name === "pagedown") { key.preventDefault(); output.scrollBy(key.name === "pageup" ? -5 : 5); }
  };
  search.on(InputRenderableEvents.INPUT, onInput);
  renderer.keyInput.on("keypress", onKey);
  sync();
  return { sync, search, menu, output, result, dispose: () => { search.off(InputRenderableEvents.INPUT, onInput); renderer.keyInput.off("keypress", onKey); } };
}
