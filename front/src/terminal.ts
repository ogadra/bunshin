import { createShell, deleteShell, execute, SseEventType, type SseEvent } from "./client";
import { AppError } from "./errors/AppError";
import { classifyThrown } from "./errors/classify";
import { SessionReassignedError } from "./errors/SessionReassignedError";
import { translate, type Lang } from "./i18n";

const GRAY = "\x1b[38;5;252m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const RESET = "\x1b[0m";
const PROMPT = "$ ";

const MAX_DELAY_MS = 8000;
const INITIAL_DELAY_MS = 1000;

export interface TerminalView {
  write(data: string): void;
}

export interface TerminalElements {
  form: HTMLFormElement;
  input: HTMLInputElement;
  button: HTMLButtonElement;
  status: HTMLElement;
}

/**
 * Renders an SSE event as terminal output.
 * Returns null when the event produces nothing.
 */
export const formatEvent = (event: SseEvent): string | null => {
  switch (event.type) {
    case SseEventType.STDOUT:
      return event.data;
    case SseEventType.STDERR:
      return `${GRAY}${event.data}${RESET}`;
    case SseEventType.COMPLETE:
      return event.exitCode === 0 ? null : `${RED}exit code: ${String(event.exitCode)}${RESET}\n`;
  }
};

export interface History {
  push(command: string): void;
  prev(): string | null;
  next(): string | null;
}

/** Command history walked with the arrow keys, newest last. */
export const createHistory = (): History => {
  const entries: string[] = [];
  let cursor = 0;
  return {
    push(command) {
      entries.push(command);
      cursor = entries.length;
    },
    prev() {
      if (cursor === 0) return null;
      cursor -= 1;
      return entries[cursor];
    },
    next() {
      if (cursor >= entries.length) return null;
      cursor += 1;
      return cursor === entries.length ? "" : entries[cursor];
    },
  };
};

const messageOf = (lang: Lang, err: unknown): string => {
  const classified = err instanceof AppError ? err : classifyThrown(err);
  return translate(lang, classified.key);
};

export const initTerminal = (view: TerminalView, els: TerminalElements, lang: Lang): void => {
  const { form, input, button, status } = els;
  const history = createHistory();
  let running = false;

  const writeLine = (text: string): void => {
    view.write(`${text}\n`);
  };

  const setDisabled = (disabled: boolean): void => {
    input.disabled = disabled;
    button.disabled = disabled;
  };

  const focusCommand = (): void => {
    // 接続完了とコマンド完了は非同期に起きる。
    // 他要素へ移ったフォーカスは奪わない
    const active = document.activeElement;
    if (active === null || active === document.body || active === input) input.focus();
  };

  const connectAbort = new AbortController();
  let execAbort: AbortController | null = null;

  const connect = async (delay: number): Promise<void> => {
    try {
      await createShell(connectAbort.signal);
      if (connectAbort.signal.aborted) return;
      status.hidden = true;
      setDisabled(false);
      view.write(PROMPT);
      focusCommand();
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      if (connectAbort.signal.aborted) return;
      status.textContent = `${messageOf(lang, err)} ${translate(lang, "termRetrying")}`;
      setTimeout(() => {
        if (!connectAbort.signal.aborted) void connect(Math.min(delay * 2, MAX_DELAY_MS));
      }, delay);
    }
  };

  const beginReconnect = (): void => {
    status.hidden = false;
    status.textContent = translate(lang, "termConnecting");
    void connect(INITIAL_DELAY_MS);
  };

  const run = async (): Promise<void> => {
    const command = input.value.trim();
    if (command === "" || running) return;
    input.value = "";
    history.push(command);
    running = true;
    setDisabled(true);
    writeLine(command);

    const controller = new AbortController();
    execAbort = controller;
    let shellLost = false;

    try {
      for await (const event of execute(command, controller.signal)) {
        const text = formatEvent(event);
        if (text !== null) view.write(text);
      }
    } catch (err: unknown) {
      if (controller.signal.aborted) return;
      if (err instanceof SessionReassignedError) {
        // 別 runner に張り替わっており、そこには shell がないので作り直す
        try {
          await createShell(controller.signal);
          writeLine(`${YELLOW}${translate(lang, "termSessionRecreated")}${RESET}`);
        } catch (createErr: unknown) {
          if (controller.signal.aborted) return;
          writeLine(`${RED}${messageOf(lang, createErr)}${RESET}`);
          shellLost = true;
        }
      } else {
        writeLine(`${RED}${messageOf(lang, err)}${RESET}`);
      }
    } finally {
      if (execAbort === controller) execAbort = null;
      running = false;
      if (shellLost) {
        // shell がないままプロンプトを出すと、打てるのに必ず失敗するコマンドを誘う
        beginReconnect();
      } else {
        view.write(PROMPT);
        setDisabled(false);
        focusCommand();
      }
    }
  };

  input.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowUp" && e.key !== "ArrowDown") return;
    e.preventDefault();
    const entry = e.key === "ArrowUp" ? history.prev() : history.next();
    if (entry !== null) input.value = entry;
  });

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    void run();
  });

  window.addEventListener("beforeunload", () => {
    connectAbort.abort();
    execAbort?.abort();
    deleteShell();
  });

  beginReconnect();
};
