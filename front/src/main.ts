import { getAppHandler, putAppHandler } from "./client";
import { createPerlEditor } from "./editor";
import { AppError } from "./errors/AppError";
import { classifyThrown } from "./errors/classify";
import { startHandlerSync, type SaveStatus } from "./handlerSync";
import { detectLang, translate, type MessageKey } from "./i18n";
import { previewUrl } from "./previewUrl";
import "./style.css";

const DEBOUNCE_MS = 1000;

const lang = detectLang(navigator.language);

const bannerEl = document.createElement("div");
bannerEl.className = "error-banner";
bannerEl.hidden = true;
document.body.prepend(bannerEl);

const indicatorEl = document.createElement("div");
indicatorEl.className = "status-indicator";
indicatorEl.hidden = true;
document.body.append(indicatorEl);

const showBanner = (key: MessageKey): void => {
  bannerEl.textContent = translate(lang, key);
  bannerEl.hidden = false;
};

const renderStatus = (status: SaveStatus): void => {
  if (status === "idle") {
    indicatorEl.hidden = true;
    return;
  }
  const key: MessageKey =
    status === "saving" ? "statusSaving" : status === "saved" ? "statusSaved" : "statusError";
  indicatorEl.textContent = translate(lang, key);
  indicatorEl.dataset.status = status;
  indicatorEl.hidden = false;
};

const readTemplate = (): string => {
  const template = import.meta.env.VITE_PERL_ORIGIN_TEMPLATE;
  if (!template) {
    console.error("VITE_PERL_ORIGIN_TEMPLATE is required (see front/.env.example)");
    throw new AppError("errorInternal");
  }
  return template;
};

type PreviewController = {
  reload: () => void;
  setSession: (hex: string, stack: string) => void;
};

const createPreviewController = (
  iframe: HTMLIFrameElement,
  template: string,
  hex: string,
  stack: string,
): PreviewController => {
  let currentHex = hex;
  let currentStack = stack;
  return {
    reload: () => {
      // 同じURLを代入してもreloadしないブラウザがあるためcache-busterを付ける
      const base = previewUrl(template, currentHex, currentStack);
      iframe.src = `${base}?_=${String(performance.now())}`;
    },
    setSession: (nextHex, nextStack) => {
      currentHex = nextHex;
      currentStack = nextStack;
    },
  };
};

const boot = async (): Promise<void> => {
  const template = readTemplate();
  const editorEl = document.getElementById("editor") as HTMLElement;
  const iframe = document.getElementById("preview") as HTMLIFrameElement;

  const { source, sessionHex, stackName } = await getAppHandler();
  const editor = createPerlEditor(editorEl, source);
  const preview = createPreviewController(iframe, template, sessionHex, stackName);
  preview.reload();

  startHandlerSync({
    editor,
    initialCode: source,
    putHandler: async (next: string): Promise<void> => {
      const res = await putAppHandler(next);
      preview.setSession(res.sessionHex, res.stackName);
      if (res.reassigned) showBanner("errorSessionLost");
    },
    reloadPreview: preview.reload,
    debounceMs: DEBOUNCE_MS,
    onPutFailure: (err) => {
      showBanner(classifyThrown(err).key);
    },
    onStatusChange: renderStatus,
  });
};

boot().catch((err: unknown) => {
  showBanner(classifyThrown(err).key);
});
