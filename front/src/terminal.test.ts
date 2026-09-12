// @vitest-environment happy-dom
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { SseEventType } from "./client";
import { createHistory, formatEvent, initTerminal, type TerminalView } from "./terminal";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
  document.body.innerHTML = "";
});

describe("formatEvent", () => {
  test("stdout is written as-is", () => {
    expect(formatEvent({ type: SseEventType.STDOUT, data: "hello" })).toBe("hello");
  });

  test("stderr is dimmed", () => {
    expect(formatEvent({ type: SseEventType.STDERR, data: "warn" })).toBe(
      "\x1b[38;5;252mwarn\x1b[0m",
    );
  });

  test("exit code 0 produces no output", () => {
    expect(formatEvent({ type: SseEventType.COMPLETE, exitCode: 0 })).toBeNull();
  });

  test("a non-zero exit code is reported in red", () => {
    expect(formatEvent({ type: SseEventType.COMPLETE, exitCode: 2 })).toBe(
      "\x1b[31mexit code: 2\x1b[0m\n",
    );
  });
});

describe("createHistory", () => {
  test("an empty history yields nothing", () => {
    const history = createHistory();
    expect(history.prev()).toBeNull();
    expect(history.next()).toBeNull();
  });

  test("prev walks backwards from the newest entry", () => {
    const history = createHistory();
    history.push("first");
    history.push("second");
    expect(history.prev()).toBe("second");
    expect(history.prev()).toBe("first");
    expect(history.prev()).toBeNull();
  });

  test("next walks forward and clears the input past the newest entry", () => {
    const history = createHistory();
    history.push("first");
    history.push("second");
    history.prev();
    history.prev();
    expect(history.next()).toBe("second");
    expect(history.next()).toBe("");
    expect(history.next()).toBeNull();
  });

  test("a new entry resets the cursor to the newest", () => {
    const history = createHistory();
    history.push("first");
    history.prev();
    history.push("second");
    expect(history.prev()).toBe("second");
  });
});

const setup = () => {
  document.body.innerHTML = `
    <form id="input-bar"><input id="command" disabled /><button disabled></button></form>
    <div id="status"></div>
  `;
  const form = document.getElementById("input-bar") as HTMLFormElement;
  const els = {
    form,
    input: document.getElementById("command") as HTMLInputElement,
    button: form.querySelector("button") as HTMLButtonElement,
    status: document.getElementById("status") as HTMLElement,
  };
  const written: string[] = [];
  const view: TerminalView = {
    write: (data) => {
      written.push(data);
    },
  };
  return { els, view, written };
};

const flush = async (): Promise<void> => {
  await vi.advanceTimersByTimeAsync(0);
};

describe("initTerminal", () => {
  // 接続失敗は再試行タイマーを積む。
  // 実タイマーのままだとテストを跨いで発火する
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  test("a successful shell creation enables the input and prints the prompt", async () => {
    const { els, view, written } = setup();
    mockFetch.mockResolvedValue({ ok: true });

    initTerminal(view, els, "en");
    expect(els.status.textContent).toBe("Connecting…");
    await flush();

    expect(els.status.hidden).toBe(true);
    expect(els.input.disabled).toBe(false);
    expect(els.button.disabled).toBe(false);
    expect(written).toEqual(["$ "]);
  });

  test("a failed shell creation keeps the status visible with the reason", async () => {
    const { els, view } = setup();
    mockFetch.mockResolvedValue({
      ok: false,
      status: 503,
      headers: { get: () => null },
      clone: () => ({ json: async () => ({ code: "NO_IDLE_RUNNER" }) }),
    });

    initTerminal(view, els, "ja");
    await flush();

    expect(els.status.hidden).toBe(false);
    expect(els.status.textContent).toBe("実行環境に空きがありません 再試行します…");
    expect(els.input.disabled).toBe(true);
  });

  test("a retry that succeeds hides the status and enables the input", async () => {
    const { els, view, written } = setup();
    mockFetch
      .mockResolvedValueOnce({
        ok: false,
        status: 503,
        headers: { get: () => null },
        clone: () => ({ json: async () => ({ code: "NO_IDLE_RUNNER" }) }),
      })
      .mockResolvedValue({ ok: true });

    initTerminal(view, els, "en");
    await vi.advanceTimersByTimeAsync(0);
    expect(els.input.disabled).toBe(true);

    await vi.advanceTimersByTimeAsync(1000);

    expect(els.status.hidden).toBe(true);
    expect(els.input.disabled).toBe(false);
    expect(written).toEqual(["$ "]);
  });

  test("a failed shell recreation keeps the input disabled and falls back to reconnecting", async () => {
    const { els, view, written } = setup();
    let shellCalls = 0;
    mockFetch.mockImplementation((url: string) => {
      if (url === "/api/shell") {
        shellCalls += 1;
        if (shellCalls === 1) return Promise.resolve({ ok: true });
        return Promise.resolve({
          ok: false,
          status: 503,
          headers: { get: () => null },
          clone: () => ({ json: async () => ({ code: "NO_IDLE_RUNNER" }) }),
        });
      }
      return Promise.resolve({
        ok: false,
        status: 400,
        headers: { get: (name: string) => (name === "X-Session-Reassigned" ? "true" : null) },
      });
    });

    initTerminal(view, els, "ja");
    await flush();
    els.input.value = "date";
    els.form.dispatchEvent(new Event("submit"));
    await flush();

    expect(els.input.disabled).toBe(true);
    expect(els.button.disabled).toBe(true);
    expect(els.status.hidden).toBe(false);
    expect(els.status.textContent).toBe("実行環境に空きがありません 再試行します…");
    expect(written).toEqual(["$ ", "date\n", "\x1b[31m実行環境に空きがありません\x1b[0m\n"]);
  });

  test("a shell recreation aborted by the unload does not start reconnecting", async () => {
    const { els, view } = setup();
    const created: Array<string | undefined> = [];
    mockFetch.mockImplementation((url: string, init: { method?: string; signal?: AbortSignal }) => {
      if (url !== "/api/shell") {
        return Promise.resolve({
          ok: false,
          status: 400,
          headers: { get: (name: string) => (name === "X-Session-Reassigned" ? "true" : null) },
        });
      }
      created.push(init.method);
      if (created.length === 1) return Promise.resolve({ ok: true });
      if (init.method === "DELETE") return Promise.resolve({ ok: true });
      return new Promise((_, reject) => {
        init.signal?.addEventListener("abort", () => {
          reject(new DOMException("aborted", "AbortError"));
        });
      });
    });

    initTerminal(view, els, "en");
    await flush();
    els.input.value = "date";
    els.form.dispatchEvent(new Event("submit"));
    await flush();

    window.dispatchEvent(new Event("beforeunload"));
    await flush();

    expect(created.filter((method) => method === "POST")).toHaveLength(2);
  });

  test("the arrow keys replace the input with history entries", async () => {
    const { els, view } = setup();
    mockFetch.mockResolvedValue({ ok: true });
    initTerminal(view, els, "en");
    await flush();

    els.input.value = "date";
    els.form.dispatchEvent(new Event("submit"));
    await flush();

    els.input.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp" }));
    expect(els.input.value).toBe("date");
    els.input.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown" }));
    expect(els.input.value).toBe("");
  });

  test("an empty command is not submitted", async () => {
    const { els, view } = setup();
    mockFetch.mockResolvedValue({ ok: true });
    initTerminal(view, els, "en");
    await flush();
    mockFetch.mockReset();

    els.input.value = "   ";
    els.form.dispatchEvent(new Event("submit"));
    await flush();

    expect(mockFetch).not.toHaveBeenCalled();
  });
});
