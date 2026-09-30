import type { CatalogItem, DispatchResult, Helper } from "./protocol.ts";

export function filterCatalog(items: CatalogItem[], query: string): CatalogItem[] {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  return items.filter(item => {
    const haystack = `${item.title} ${item.subtitle} ${item.keywords}`.toLowerCase();
    return tokens.every(token => haystack.includes(token));
  });
}
export interface ViewState {
  items: CatalogItem[]; query: string; selected: number;
  loading: boolean; busy: boolean; hidden: boolean; composing: boolean;
  result: DispatchResult | null; error: string | null;
}
export type SavedResult = { kind: "pending"; actionID: string; requestID: string } | { kind: "result"; result: DispatchResult } | { kind: "error"; message: string };
export interface AppOptions {
  onChange?: (state: ViewState) => void;
  onHide?: () => void;
  save?: (result: SavedResult) => Promise<void>;
  requestID?: () => string;
}
export class Palette {
  readonly state: ViewState = { items: [], query: "", selected: 0, loading: true, busy: false, hidden: false, composing: false, result: null, error: null };
  private pending: Promise<void> = Promise.resolve();
  constructor(readonly helper: Helper, readonly options: AppOptions = {}) {}
  get visible(): CatalogItem[] { return filterCatalog(this.state.items, this.state.query); }
  private change(): void { this.options.onChange?.(this.state); }
  async load(): Promise<void> {
    try { this.state.items = await this.helper.catalog(); }
    catch (error) { this.state.error = String(error instanceof Error ? error.message : error); }
    finally { this.state.loading = false; this.change(); }
  }
  restore(saved: SavedResult): void {
    if (saved.kind === "result") this.state.result = saved.result;
    else this.state.error = saved.kind === "error" ? saved.message : `前回の ${saved.actionID} の結果は未確認です。自動再送しません。`;
    this.change();
  }
  setQuery(query: string): void { this.state.query = query; this.state.selected = 0; this.change(); }
  move(delta: number): void {
    const max = this.visible.length - 1;
    this.state.selected = max < 0 ? 0 : Math.max(0, Math.min(max, this.state.selected + delta));
    this.change();
  }
  setComposing(value: boolean): void { this.state.composing = value; }
  hide(): void {
    if (this.state.hidden) return;
    this.state.hidden = true;
    this.options.onHide?.();
    this.change();
  }
  async settled(): Promise<void> { await this.pending; }
  execute(): Promise<void> {
    const item = this.visible[this.state.selected];
    if (!item || this.state.hidden || this.state.busy || this.state.loading || this.state.composing) return Promise.resolve();
    this.state.busy = true;
    this.state.error = null;
    const requestID = this.options.requestID?.() ?? crypto.randomUUID();
    // Hide before dispatch; destroying the UI must not terminate this promise.
    if (item.kind === "application") this.hide();
    this.change();
    this.pending = this.dispatch(item, requestID);
    return this.pending;
  }
  private async dispatch(item: CatalogItem, requestID: string): Promise<void> {
    try {
      await this.options.save?.({ kind: "pending", actionID: item.id, requestID });
      const result = await this.helper.dispatch(item.id, requestID);
      this.state.result = result;
      await this.options.save?.({ kind: "result", result });
    } catch (error) {
      this.state.error = error instanceof Error ? error.message : String(error);
      try { await this.options.save?.({ kind: "error", message: this.state.error }); }
      catch (saveError) { this.state.error += `\n結果の保存にも失敗: ${String(saveError)}`; }
    } finally { this.state.busy = false; this.change(); }
  }
}

export function resultText(state: ViewState): string {
  if (state.error) return `エラー\n${state.error}`;
  if (state.busy) return "実行中…（再送しません）";
  if (state.result) {
    const r = state.result;
    const data = r.data ? `\n${JSON.stringify(r.data, null, 2)}` : "";
    return `${r.status === "ok" ? "完了" : "エラー"} · ${r.title ?? r.actionID}\n${r.message}${data}`;
  }
  return "操作を選ぶと、ここに実行結果を表示します。";
}
