import { expect, test } from "bun:test";
import { parseCatalog, parseConfig, parseDispatch } from "../src/protocol.ts";
import { catalog } from "./fixtures.ts";

test("protocol rejects invalid status, duplicate catalog IDs and mismatched dispatch identity", () => {
  expect(parseCatalog({ protocolVersion: 1, status: "ok", items: catalog })).toEqual(catalog);
  expect(() => parseCatalog({ protocolVersion: 1, status: "maybe", items: catalog })).toThrow("status");
  expect(() => parseCatalog({ protocolVersion: 1, status: "ok", items: [catalog[0], catalog[0]] })).toThrow("重複");
  expect(() => parseDispatch({ protocolVersion: 1, status: "ok", requestID: "old", actionID: "terminal.step", message: "wrong request" }, "terminal.step", "new")).toThrow("一致");
  expect(() => parseDispatch({ protocolVersion: 1, status: "ok", requestID: "r", actionID: "wrong", message: "wrong action" }, "terminal.step", "r")).toThrow("一致");
  expect(() => parseConfig({ protocolVersion: 1, helperPath: "relative", stateDir: "/tmp/state", cwd: "/tmp" })).toThrow("絶対パス");
});
