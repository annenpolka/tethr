export interface Item { id: string; title: string; subtitle: string; keywords: string; kind: "terminal" | "command" | "application" }
export interface Reply { protocolVersion: 1; status: "ok" | "error"; requestID?: string; actionID?: string; title?: string; message?: string; errorCode?: string; data?: unknown; items?: Item[] }
export interface Bridge { catalog(): Promise<Reply>; dispatch(actionID: string, requestID: string): Promise<Reply>; hide(): Promise<void> }

export function filterItems(items: Item[], query: string): Item[] {
  const tokens = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
  return items.filter(item => tokens.every(token => `${item.title} ${item.subtitle} ${item.keywords}`.toLowerCase().includes(token)));
}

export function describeReply(reply: Reply): string {
  const heading = reply.status === "error" ? `失敗${reply.errorCode ? ` (${reply.errorCode})` : ""}` : "結果";
  return [heading, reply.title, reply.message, reply.data === undefined ? undefined : JSON.stringify(reply.data, null, 2)].filter(v => v !== undefined).join("\n");
}

export class Launcher {
  items: Item[] = [];
  query = "";
  selected = 0;
  loading = true;
  busy = false;
  output = "候補を読み込み中…";
  error = false;
  private generation = 0;
  constructor(readonly bridge: Bridge, readonly changed: () => void, readonly nextID: () => string = () => crypto.randomUUID()) {}
  get visible() { return filterItems(this.items, this.query); }
  async load() {
    const generation = ++this.generation;
    this.loading = true; this.changed();
    try {
      const response = await this.bridge.catalog();
      if (generation !== this.generation) return;
      if (response.status !== "ok" || !Array.isArray(response.items)) throw new Error(response.message ?? "候補を読み込めませんでした");
      this.items = response.items; this.selected = 0; this.output = "操作を選んで Enter"; this.error = false;
    } catch (error) {
      if (generation !== this.generation) return;
      this.items = []; this.output = String(error); this.error = true;
    } finally {
      if (generation === this.generation) { this.loading = false; this.changed(); }
    }
  }
  search(query: string) { this.query = query; this.selected = 0; this.changed(); }
  move(delta: number) {
    const count = this.visible.length;
    this.selected = count ? (this.selected + delta + count) % count : 0;
    this.changed();
  }
  async execute() {
    const item = this.visible[this.selected];
    if (!item || this.busy || this.loading) return;
    const requestID = this.nextID();
    this.busy = true; this.error = false; this.output = `${item.title}\n実行中…`; this.changed();
    try {
      if (item.kind === "application") await this.bridge.hide();
      const reply = await this.bridge.dispatch(item.id, requestID);
      if (reply.protocolVersion !== 1 || !["ok", "error"].includes(reply.status) || reply.actionID !== item.id || reply.requestID !== requestID) {
        throw new Error("応答の識別が一致しません。到達状態は不明です。自動再送はしません。");
      }
      this.output = describeReply({ ...reply, title: item.title }); this.error = reply.status === "error";
    } catch (error) { this.output = `${item.title}\n${String(error)}`; this.error = true; }
    finally { this.busy = false; this.changed(); }
  }
  async hide() {
    try { await this.bridge.hide(); }
    catch (error) { this.output = String(error); this.error = true; this.changed(); }
  }
}

// Composition/key events are component-level protection; real WKWebView + macOS IME is separately accepted.
export class CompositionGuard {
  composing = false;
  endedBeforeKeyUp = false;
  start() { this.composing = true; this.endedBeforeKeyUp = false; }
  end() { this.composing = false; this.endedBeforeKeyUp = true; }
  release() { this.endedBeforeKeyUp = false; }
  blocked(event: Pick<KeyboardEvent, "isComposing" | "keyCode">) { return this.composing || this.endedBeforeKeyUp || event.isComposing || event.keyCode === 229; }
}
