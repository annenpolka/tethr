import type { CatalogItem, DispatchResult, Helper } from "../src/protocol.ts";

// UI-only substitute. Production always uses ProcessHelper and the common backend.
export const catalog: CatalogItem[] = [
  { id: "terminal.step", title: "同じシェルで続ける", subtitle: "試験用 tmux の状態を確認・更新", keywords: "terminal shell tmux ターミナル 続き", kind: "terminal" },
  { id: "command.git-status", title: "変更状況を見る", subtitle: "設定したリポジトリの git status", keywords: "git status changes 変更 リポジトリ", kind: "command" },
  { id: "app.fixture-b", title: "受信アプリ B", subtitle: "run-or-raise", keywords: "application app fixture アプリ", kind: "application" },
];
export function deferred<T>() { let resolve!: (value: T) => void; let reject!: (error: Error) => void; const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
export class UIOnlyHelper implements Helper {
  calls: { actionID: string; requestID: string }[] = [];
  reply?: (actionID: string, requestID: string) => Promise<DispatchResult>;
  async catalog() { return catalog; }
  async dispatch(actionID: string, requestID: string): Promise<DispatchResult> {
    this.calls.push({ actionID, requestID });
    return this.reply?.(actionID, requestID) ?? { protocolVersion: 1, status: "ok", actionID, requestID, message: "UI試験用の応答", data: { counter: 7 } };
  }
}
