import { getAppHandler, putAppHandler } from "./client";
import { createPerlEditor, type PerlEditorHandle } from "./editor";
import { previewUrl, sessionHexFromCookie } from "./previewUrl";
import { samplePerl } from "./samplePerl";
import "./style.css";

// Perl 側は `do` で毎リクエスト再読込するので、送信完了直後の iframe fetch は必ず新版を返す。
// debounce は編集の手が止まった判定に使う時間で、送信間隔ではない
const DEBOUNCE_MS = 1000;

const PERL_ORIGIN_TEMPLATE = import.meta.env.VITE_PERL_ORIGIN_TEMPLATE;
if (!PERL_ORIGIN_TEMPLATE) {
  throw new Error("VITE_PERL_ORIGIN_TEMPLATE is required (see front/.env.example)");
}

const editorEl = document.getElementById("editor") as HTMLElement;
const iframe = document.getElementById("preview") as HTMLIFrameElement;

const initialCode = await getAppHandler().catch((err: unknown) => {
  console.warn("GET /api/app/handler failed, falling back to sample", err);
  return samplePerl;
});

const editor: PerlEditorHandle = createPerlEditor(editorEl, initialCode);

let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let inFlight = false;
let lastSent: string | null = initialCode;

const reloadPreview = (): void => {
  const hex = sessionHexFromCookie(document.cookie);
  if (hex === null) {
    console.warn("session_id cookie missing; skipping preview reload");
    return;
  }
  const base = previewUrl(PERL_ORIGIN_TEMPLATE, hex);
  // 同じ URL を代入しても reload しないブラウザがあるため、cache-buster を付ける
  iframe.src = `${base}?_=${String(performance.now())}`;
};

reloadPreview();

const scheduleFlush = (): void => {
  if (debounceTimer !== null) clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debounceTimer = null;
    void flush();
  }, DEBOUNCE_MS);
};

const flush = async (): Promise<void> => {
  if (inFlight) return;
  const snapshot = editor.value;
  if (snapshot === lastSent) return;
  inFlight = true;
  try {
    await putAppHandler(snapshot);
    lastSent = snapshot;
    reloadPreview();
  } catch (err: unknown) {
    console.error("PUT /api/app/handler failed", err);
  } finally {
    inFlight = false;
    // PUT 中に debounce timer が inFlight で drop されると、次の onChange が来ない限り誰も拾わない。
    // timer 未セットのときだけここから張り直す
    if (editor.value !== lastSent && debounceTimer === null) scheduleFlush();
  }
};

editor.onChange(scheduleFlush);
