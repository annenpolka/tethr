import { isAbsolute } from "node:path";

export interface CatalogItem {
  id: string; title: string; subtitle: string; keywords: string;
  kind: "terminal" | "command" | "application";
}
export interface DispatchResult {
  protocolVersion: 1; status: "ok" | "error";
  requestID: string; actionID: string; message: string;
  title?: string; errorCode?: string; data?: Record<string, unknown>;
}
export interface Config { protocolVersion: 1; helperPath: string; stateDir: string; cwd: string }
export interface Helper {
  catalog(): Promise<CatalogItem[]>;
  dispatch(actionID: string, requestID: string): Promise<DispatchResult>;
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("応答がJSON objectではありません");
  return value as Record<string, unknown>;
}
function text(value: unknown, label: string): string {
  if (typeof value !== "string") throw new Error(`${label}が文字列ではありません`);
  return value;
}
function envelope(value: unknown): Record<string, unknown> {
  const obj = record(value);
  if (obj.protocolVersion !== 1 || !["ok", "error"].includes(String(obj.status))) throw new Error("helper protocol/statusが不正です");
  return obj;
}
export function parseConfig(value: unknown): Config {
  const obj = record(value);
  if (obj.protocolVersion !== 1) throw new Error("config protocolVersionは1が必要です");
  const helperPath = text(obj.helperPath, "helperPath"), stateDir = text(obj.stateDir, "stateDir"), cwd = text(obj.cwd, "cwd");
  if (![helperPath, stateDir, cwd].every(isAbsolute)) throw new Error("helperPath/stateDir/cwdは絶対パスが必要です");
  return { protocolVersion: 1, helperPath, stateDir, cwd };
}
export function parseCatalog(value: unknown): CatalogItem[] {
  const obj = envelope(value);
  if (obj.status === "error") throw new Error(text(obj.message, "message"));
  if (!Array.isArray(obj.items)) throw new Error("catalog itemsが配列ではありません");
  const ids = new Set<string>();
  return obj.items.map((value) => {
    const item = record(value), id = text(item.id, "id"), kind = item.kind;
    if (!id || ids.has(id)) throw new Error("catalog idが空または重複しています");
    if (kind !== "terminal" && kind !== "command" && kind !== "application") throw new Error("catalog kindが不正です");
    ids.add(id);
    return { id, kind, title: text(item.title, "title"), subtitle: text(item.subtitle, "subtitle"), keywords: text(item.keywords, "keywords") };
  });
}
export function parseDispatch(value: unknown, actionID: string, requestID: string): DispatchResult {
  const obj = envelope(value);
  if (obj.requestID !== requestID || obj.actionID !== actionID) throw new Error("helperのrequestID/actionIDが一致しません（結果不明）");
  const result: DispatchResult = { protocolVersion: 1, status: obj.status as "ok" | "error", requestID, actionID, message: text(obj.message, "message") };
  if (obj.title !== undefined) result.title = text(obj.title, "title");
  if (obj.errorCode !== undefined) result.errorCode = text(obj.errorCode, "errorCode");
  if (obj.data !== undefined) result.data = record(obj.data);
  return result;
}

export class ProcessHelper implements Helper {
  constructor(readonly configPath: string, readonly config: Config, readonly timeoutMs = 30_000) {}
  private async call(args: string[]): Promise<unknown> {
    const proc = Bun.spawn([this.config.helperPath, "--config", this.configPath, ...args], { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const normal = Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited]);
      const deadline = new Promise<never>((_, reject) => {
        timer = setTimeout(() => { proc.kill("SIGTERM"); reject(new Error("helperの応答が時間内に届きません。実行結果は不明です。自動再送しません。")); }, this.timeoutMs);
      });
      const [stdout, stderr, code] = await Promise.race([normal, deadline]);
      if (code !== 0) throw new Error(`helper終了コード ${code}: ${stderr.trim() || stdout.trim() || "詳細なし"}`);
      try { return JSON.parse(stdout); } catch { throw new Error("helper stdoutが単一のJSON応答ではありません"); }
    } finally { if (timer) clearTimeout(timer); }
  }
  async catalog(): Promise<CatalogItem[]> { return parseCatalog(await this.call(["catalog"])); }
  async dispatch(actionID: string, requestID: string): Promise<DispatchResult> {
    return parseDispatch(await this.call(["dispatch", actionID, "--request-id", requestID]), actionID, requestID);
  }
}
