import type { PerlEditorHandle } from "./editor";

export type HandlerSyncDeps = {
  editor: PerlEditorHandle;
  initialCode: string;
  putHandler: (source: string) => Promise<void>;
  reloadPreview: () => void;
  debounceMs: number;
  onPutFailure: (err: unknown) => void;
};

export const startHandlerSync = (deps: HandlerSyncDeps): void => {
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let inFlight = false;
  let lastSent: string = deps.initialCode;
  let stopped = false;

  const scheduleFlush = (): void => {
    if (stopped) return;
    if (debounceTimer !== null) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      void flush();
    }, deps.debounceMs);
  };

  const flush = async (): Promise<void> => {
    if (inFlight || stopped) return;
    const snapshot = deps.editor.value;
    if (snapshot === lastSent) return;
    inFlight = true;
    try {
      await deps.putHandler(snapshot);
      lastSent = snapshot;
      deps.reloadPreview();
    } catch (err: unknown) {
      stopped = true;
      deps.onPutFailure(err);
      return;
    } finally {
      inFlight = false;
    }
    if (deps.editor.value !== lastSent && debounceTimer === null) scheduleFlush();
  };

  deps.editor.onChange(scheduleFlush);
};
