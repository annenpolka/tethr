import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { mount } from "./ui";
import type { Reply } from "./model";
import "./style.css";

mount(document.querySelector<HTMLElement>("#app")!, {
  catalog: () => invoke<Reply>("load_catalog"),
  dispatch: (actionID, requestID) => invoke<Reply>("dispatch_action", { actionId: actionID, requestId: requestID }),
  hide: () => getCurrentWindow().hide(),
});
