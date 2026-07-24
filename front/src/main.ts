import { getAppHandler, putAppHandler } from "./client";
import { createPerlEditor } from "./editor";
import { AppError } from "./errors/AppError";
import { classifyThrown } from "./errors/classify";
import { SaveStatus, startHandlerSync } from "./handlerSync";
import { detectLang, translate, type MessageKey } from "./i18n";
import { previewUrl } from "./previewUrl";
import { createStackInfoDialog } from "./stackInfoDialog";
import "./style.css";

const DEBOUNCE_MS = 1000;

const lang = detectLang(navigator.language);

const editorEl = document.getElementById("editor") as HTMLElement;
const iframe = document.getElementById("preview") as HTMLIFrameElement;
const stackButton = document.getElementById("stack-info-button") as HTMLButtonElement;
const stackDialog = document.getElementById("stack-info-dialog") as HTMLDialogElement;

const bannerEl = document.createElement("div");
bannerEl.className = "error-banner";
bannerEl.hidden = true;
document.body.prepend(bannerEl);

const indicatorEl = document.createElement("div");
indicatorEl.className = "status-indicator";
indicatorEl.hidden = true;
// iframeは白背景でindicatorが読めないので、body直下ではなく暗いeditor pane内に配置する
editorEl.append(indicatorEl);

const showBanner = (key: MessageKey): void => {
  bannerEl.textContent = translate(lang, key);
  bannerEl.hidden = false;
};

const STATUS_MESSAGE: Record<SaveStatus, MessageKey> = {
  [SaveStatus.SAVING]: "statusSaving",
  [SaveStatus.SAVED]: "statusSaved",
  [SaveStatus.ERROR]: "statusError",
};

const renderStatus = (status: SaveStatus): void => {
  indicatorEl.textContent = translate(lang, STATUS_MESSAGE[status]);
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
  const { source, sessionHex, stackName } = await getAppHandler();
  const editor = createPerlEditor(editorEl, source);
  const preview = createPreviewController(iframe, template, sessionHex, stackName);
  const stackInfo = createStackInfoDialog(stackButton, stackDialog, lang, stackName);
  preview.reload();

  startHandlerSync({
    editor,
    initialCode: source,
    putHandler: async (next: string): Promise<void> => {
      const res = await putAppHandler(next);
      preview.setSession(res.sessionHex, res.stackName);
      if (res.reassigned) showBanner("errorSessionLost");
      try {
        stackInfo.setStack(res.stackName);
      } catch (err: unknown) {
        // reassigned banner を errorInternal で上書きさせないため handlerSync まで throw を運ばない
        console.error(err);
      }
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
