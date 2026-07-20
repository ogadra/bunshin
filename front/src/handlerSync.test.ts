import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { startHandlerSync } from "./handlerSync";

const createEditorStub = (initial: string) => {
  let value = initial;
  let listener: ((code: string) => void) | null = null;
  return {
    handle: {
      get value(): string {
        return value;
      },
      onChange(cb: (code: string) => void): void {
        listener = cb;
      },
    },
    type(newValue: string): void {
      value = newValue;
      listener?.(value);
    },
  };
};

describe("startHandlerSync", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  test("PUTs the latest snapshot and reloads preview after DEBOUNCE_MS of idle", async () => {
    const editor = createEditorStub("initial");
    const putHandler = vi.fn().mockResolvedValue(undefined);
    const reloadPreview = vi.fn();
    startHandlerSync({
      editor: editor.handle,
      initialCode: "initial",
      putHandler,
      reloadPreview,
      debounceMs: 100,
      onPutFailure: vi.fn(),
    });
    editor.type("edited");
    expect(putHandler).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(100);
    expect(putHandler).toHaveBeenCalledWith("edited");
    expect(reloadPreview).toHaveBeenCalledOnce();
  });

  test("does not PUT when the snapshot equals lastSent", async () => {
    const editor = createEditorStub("initial");
    const putHandler = vi.fn().mockResolvedValue(undefined);
    startHandlerSync({
      editor: editor.handle,
      initialCode: "initial",
      putHandler,
      reloadPreview: vi.fn(),
      debounceMs: 100,
      onPutFailure: vi.fn(),
    });
    editor.type("initial");
    await vi.advanceTimersByTimeAsync(100);
    expect(putHandler).not.toHaveBeenCalled();
  });

  test("waits DEBOUNCE_MS of idle after an in-flight PUT completes before the next PUT", async () => {
    const editor = createEditorStub("initial");
    let resolvePut: (() => void) | null = null;
    const putHandler = vi.fn(
      () =>
        new Promise<void>((resolve) => {
          resolvePut = resolve;
        }),
    );
    startHandlerSync({
      editor: editor.handle,
      initialCode: "initial",
      putHandler,
      reloadPreview: vi.fn(),
      debounceMs: 100,
      onPutFailure: vi.fn(),
    });
    editor.type("first");
    await vi.advanceTimersByTimeAsync(100);
    expect(putHandler).toHaveBeenCalledTimes(1);

    editor.type("second");
    expect(putHandler).toHaveBeenCalledTimes(1);

    resolvePut?.();
    await vi.advanceTimersByTimeAsync(0);
    expect(putHandler).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(99);
    expect(putHandler).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(1);
    expect(putHandler).toHaveBeenCalledTimes(2);
    expect(putHandler).toHaveBeenLastCalledWith("second");
  });

  test("stops auto-PUT and calls onPutFailure when PUT rejects", async () => {
    const editor = createEditorStub("initial");
    const boom = new Error("boom");
    const putHandler = vi.fn().mockRejectedValue(boom);
    const onPutFailure = vi.fn();
    const reloadPreview = vi.fn();
    startHandlerSync({
      editor: editor.handle,
      initialCode: "initial",
      putHandler,
      reloadPreview,
      debounceMs: 100,
      onPutFailure,
    });
    editor.type("edited");
    await vi.advanceTimersByTimeAsync(100);
    expect(putHandler).toHaveBeenCalledTimes(1);
    expect(onPutFailure).toHaveBeenCalledWith(boom);
    expect(reloadPreview).not.toHaveBeenCalled();

    editor.type("edited-again");
    await vi.advanceTimersByTimeAsync(500);
    expect(putHandler).toHaveBeenCalledTimes(1);
  });
});
