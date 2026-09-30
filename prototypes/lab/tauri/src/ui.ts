import { Launcher, CompositionGuard, type Bridge } from "./model";

export function mount(root: HTMLElement, bridge: Bridge) {
  root.innerHTML = `<header><span class="wordmark">tethr</span><span class="variant">Tauri</span></header><label for="search">何をしますか</label><input id="search" type="search" placeholder="コマンド、作業、アプリを探す" autocomplete="off" spellcheck="false" role="combobox" aria-controls="results" aria-expanded="true"><ul id="results" role="listbox" aria-label="操作候補"></ul><div class="toolbar"><span id="hint"></span><button id="run" type="button">実行 ↵</button><button id="reload" type="button">再読込</button></div><pre id="output" role="status" aria-live="polite"></pre><footer>↑ ↓ 選択　Enter 実行　Esc 非表示</footer>`;
  const input = root.querySelector<HTMLInputElement>("#search")!;
  const list = root.querySelector<HTMLUListElement>("#results")!;
  const output = root.querySelector<HTMLElement>("#output")!;
  const run = root.querySelector<HTMLButtonElement>("#run")!;
  const reload = root.querySelector<HTMLButtonElement>("#reload")!;
  const hint = root.querySelector<HTMLElement>("#hint")!;
  const guard = new CompositionGuard();
  const model = new Launcher(bridge, render);
  function render() {
    list.replaceChildren();
    const items = model.visible;
    items.forEach((item, index) => {
      const row = root.ownerDocument.createElement("li");
      row.id = `result-${index}`; row.setAttribute("role", "option"); row.setAttribute("aria-selected", String(index === model.selected));
      const title = root.ownerDocument.createElement("strong"); title.textContent = item.title;
      const subtitle = root.ownerDocument.createElement("span"); subtitle.textContent = item.subtitle;
      row.append(title, subtitle);
      row.addEventListener("click", () => { model.selected = index; render(); input.focus(); });
      list.append(row);
    });
    if (!items.length) {
      const empty = root.ownerDocument.createElement("li"); empty.className = "empty"; empty.textContent = model.loading ? "読み込み中…" : "一致する操作はありません"; list.append(empty);
    }
    if (items.length) input.setAttribute("aria-activedescendant", `result-${model.selected}`); else input.removeAttribute("aria-activedescendant");
    output.textContent = model.output; output.dataset.error = String(model.error);
    run.disabled = model.busy || model.loading || !items.length;
    reload.disabled = model.busy || model.loading;
    hint.textContent = model.busy ? "実行中…" : `${items.length} 件`;
  }
  input.addEventListener("input", () => model.search(input.value));
  input.addEventListener("compositionstart", () => guard.start());
  input.addEventListener("compositionend", () => guard.end());
  input.addEventListener("keyup", () => guard.release());
  // A pointer commit does not have a corresponding keyboard release.
  root.ownerDocument.addEventListener("pointerup", () => guard.release());
  input.addEventListener("keydown", event => {
    if (guard.blocked(event)) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); model.move(event.key === "ArrowDown" ? 1 : -1); }
    else if (event.key === "Enter") { event.preventDefault(); if (!event.repeat) void model.execute(); }
  });
  root.addEventListener("keydown", event => {
    if (event.key === "Escape" && !guard.blocked(event)) { event.preventDefault(); void model.hide(); }
  });
  run.addEventListener("click", () => { if (!guard.composing) void model.execute(); });
  reload.addEventListener("click", () => void model.load());
  input.focus();
  void model.load();
  return model;
}
