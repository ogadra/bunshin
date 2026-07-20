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

const {
  source: initialCode,
  sessionHex: initialHex,
  stackName: initialStack,
} = await getAppHandler();
if (initialHex === null) {
  throw new Error("X-Session-Hex header is missing on /api/app/handler response");
}
if (initialStack === null) {
  throw new Error("X-Stack-Name header is missing on /api/app/handler response");
}
let previewHex = initialHex;
let previewStack = initialStack;

const editor = createPerlEditor(editorEl, initialCode);

const reloadPreview = (): void => {
  // 同じURLを代入してもreloadしないブラウザがあるためcache-busterを付ける
  const base = previewUrl(PERL_ORIGIN_TEMPLATE, previewHex, previewStack);
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
    const { sessionHex, stackName } = await putAppHandler(source);
    // セッション再割当てでhexや所属stackが変わったら、次のreloadから新しいpreview先を指す
    if (sessionHex !== null) previewHex = sessionHex;
    if (stackName !== null) previewStack = stackName;
  },
  reloadPreview,
  debounceMs: DEBOUNCE_MS,
  onPutFailure: (err) => {
    showError(`Failed to save handler: ${String(err)}. Reload the page to retry.`);
  },
});
