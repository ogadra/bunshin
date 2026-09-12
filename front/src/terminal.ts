import { createShell, deleteShell, startExecute, SseEventType, type SseEvent } from "./client";
import { AppError } from "./errors/AppError";
import { classifyThrown } from "./errors/classify";
import { SessionReassignedError } from "./errors/SessionReassignedError";
import { translate, type Lang } from "./i18n";
import type { OutputBlock } from "./outputBlock";
import type { Transcript } from "./transcript";

const GRAY = "\x1b[38;5;252m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const RESET = "\x1b[0m";

const MAX_DELAY_MS = 8000;
const INITIAL_DELAY_MS = 1000;

export interface TerminalElements {
  form: HTMLFormElement;
  input: HTMLInputElement;
  button: HTMLButtonElement;
  status: HTMLElement;
}

export interface TerminalController {
  run(command: string): void;
  onBusyChange(listener: (busy: boolean) => void): void;
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

export const initTerminal = (
  transcript: Transcript,
  els: TerminalElements,
  lang: Lang,
  onStack: (stackName: string) => void,
): TerminalController => {
  const { form, input, button, status } = els;
  const history = createHistory();
  let busy = true;
  let busyListener: ((busy: boolean) => void) | null = null;

  const writeLine = (block: OutputBlock, text: string): void => {
    block.write(`${text}\n`);
  };

  const setBusy = (next: boolean): void => {
    busy = next;
    input.disabled = next;
    button.disabled = next;
    busyListener?.(next);
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
      const { stackName } = await createShell(connectAbort.signal);
      if (connectAbort.signal.aborted) return;
      onStack(stackName);
      status.hidden = true;
      setBusy(false);
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

  const run = async (command: string): Promise<void> => {
    if (command === "" || busy) return;
    input.value = "";
    history.push(command);
    setBusy(true);
    const block = transcript.begin(command);

    const controller = new AbortController();
    execAbort = controller;
    let shellLost = false;

    try {
      const execution = await startExecute(command, controller.signal);
      onStack(execution.stackName);
      for await (const event of execution.events) {
        const text = formatEvent(event);
        if (text !== null) block.write(text);
      }
    } catch (err: unknown) {
      if (controller.signal.aborted) return;
      if (err instanceof SessionReassignedError) {
        // 別 runner に張り替わっており、そこには shell がないので作り直す
        try {
          const { stackName } = await createShell(controller.signal);
          onStack(stackName);
          writeLine(block, `${YELLOW}${translate(lang, "termSessionRecreated")}${RESET}`);
        } catch (createErr: unknown) {
          if (controller.signal.aborted) return;
          writeLine(block, `${RED}${messageOf(lang, createErr)}${RESET}`);
          shellLost = true;
        }
      } else {
        writeLine(block, `${RED}${messageOf(lang, err)}${RESET}`);
      }
    } finally {
      if (execAbort === controller) execAbort = null;
      block.finish();
      if (shellLost) {
        // shell がないまま入力を戻すと、打てるのに必ず失敗するコマンドを誘う
        beginReconnect();
      } else {
        setBusy(false);
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
    void run(input.value.trim());
  });

  window.addEventListener("beforeunload", () => {
    connectAbort.abort();
    execAbort?.abort();
    deleteShell();
  });

  beginReconnect();

  return {
    run(command: string): void {
      void run(command);
    },
    onBusyChange(listener: (busy: boolean) => void): void {
      busyListener = listener;
      listener(busy);
    },
  };
};
