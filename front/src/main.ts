import { getAppHandler, putAppHandler } from "./client";
import { createPerlEditor } from "./editor";
import { startHandlerSync } from "./handlerSync";
import { previewUrl, sessionHexFromCookie } from "./previewUrl";
import "./style.css";

const DEBOUNCE_MS = 1000;

const PERL_ORIGIN_TEMPLATE = import.meta.env.VITE_PERL_ORIGIN_TEMPLATE;
if (!PERL_ORIGIN_TEMPLATE) {
  throw new Error("VITE_PERL_ORIGIN_TEMPLATE is required (see front/.env.example)");
}

const hex = sessionHexFromCookie(document.cookie);
if (hex === null) {
  throw new Error("session_id cookie is required to render the preview");
}
const previewBase = previewUrl(PERL_ORIGIN_TEMPLATE, hex);

const editorEl = document.getElementById("editor") as HTMLElement;
const iframe = document.getElementById("preview") as HTMLIFrameElement;

const initialCode = await getAppHandler();
const editor = createPerlEditor(editorEl, initialCode);

const reloadPreview = (): void => {
  // 同じ URL を代入しても reload しないブラウザがあるため cache-buster を付ける
  iframe.src = `${previewBase}?_=${String(performance.now())}`;
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
  putHandler: putAppHandler,
  reloadPreview,
  debounceMs: DEBOUNCE_MS,
  onPutFailure: (err) => {
    showError(`Failed to save handler: ${String(err)}. Reload the page to retry.`);
  },
});
