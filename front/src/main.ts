import { getAppHandler, putAppHandler } from "./client";
import { createPerlEditor } from "./editor";
import { startHandlerSync } from "./handlerSync";
import { previewUrl } from "./previewUrl";
import "./style.css";

const DEBOUNCE_MS = 1000;

const PERL_ORIGIN_TEMPLATE = import.meta.env.VITE_PERL_ORIGIN_TEMPLATE;
if (!PERL_ORIGIN_TEMPLATE) {
  throw new Error("VITE_PERL_ORIGIN_TEMPLATE is required (see front/.env.example)");
}

const editorEl = document.getElementById("editor") as HTMLElement;
const iframe = document.getElementById("preview") as HTMLIFrameElement;

const { source: initialCode, sessionHex: initialHex } = await getAppHandler();
if (initialHex === null) {
  throw new Error("X-Session-Hex header is missing on /api/app/handler response");
}
let previewHex = initialHex;

const editor = createPerlEditor(editorEl, initialCode);

const reloadPreview = (): void => {
  // 同じ URL を代入しても reload しないブラウザがあるため cache-buster を付ける
  const base = previewUrl(PERL_ORIGIN_TEMPLATE, previewHex);
  iframe.src = `${base}?_=${String(performance.now())}`;
};

const showError = (message: string): void => {
  const banner = document.createElement("div");
  banner.className = "error-banner";
  banner.textContent = message;
  document.body.prepend(banner);
};

reloadPreview();

startHandlerSync({
  editor,
  initialCode,
  putHandler: async (source: string): Promise<void> => {
    const { sessionHex } = await putAppHandler(source);
    // セッション再割当てで hex が変わったら、次の reload から新しい preview 先を指す
    if (sessionHex !== null) previewHex = sessionHex;
  },
  reloadPreview,
  debounceMs: DEBOUNCE_MS,
  onPutFailure: (err) => {
    showError(`Failed to save handler: ${String(err)}. Reload the page to retry.`);
  },
});
