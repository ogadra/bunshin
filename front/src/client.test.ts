import { describe, test, expect, vi, beforeEach } from "vitest";
import {
  createShell,
  deleteShell,
  execute,
  getAppHandler,
  putAppHandler,
  SseEventType,
} from "./client";
import { SessionReassignedError } from "./errors/SessionReassignedError";

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
});

const textEncoder = new TextEncoder();

const responseHeaders = (values: Record<string, string> = {}) => ({
  get: (name: string) => values[name] ?? null,
});

const sseBody = (lines: string[]) => {
  const encoded = textEncoder.encode(lines.join("\n") + "\n");
  let read = false;
  return {
    headers: responseHeaders(),
    body: {
      getReader: () => ({
        read: async () => {
          if (read) return { done: true, value: undefined };
          read = true;
          return { done: false, value: encoded };
        },
        cancel: vi.fn(),
      }),
    },
  };
};

describe("getAppHandler", () => {
  test("GET /api/app/handler returns text body", async () => {
    mockFetch.mockResolvedValue({ ok: true, text: async () => "sub { };" });
    await expect(getAppHandler()).resolves.toBe("sub { };");
    expect(mockFetch).toHaveBeenCalledWith("/api/app/handler", { signal: undefined });
  });

  test("throws on non-ok response", async () => {
    mockFetch.mockResolvedValue({ ok: false, status: 500 });
    await expect(getAppHandler()).rejects.toThrow("Failed to get handler: 500");
  });
});

describe("putAppHandler", () => {
  test("PUT /api/app/handler with body", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    await putAppHandler("sub { return (200, 'text/plain', 'ok'); };");
    expect(mockFetch).toHaveBeenCalledWith("/api/app/handler", {
      method: "PUT",
      body: "sub { return (200, 'text/plain', 'ok'); };",
      signal: undefined,
    });
  });

  test("throws on non-ok response", async () => {
    mockFetch.mockResolvedValue({ ok: false, status: 400 });
    await expect(putAppHandler("body")).rejects.toThrow("Failed to put handler: 400");
  });
});

describe("createShell", () => {
  test("POST /api/shell", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    await createShell();
    expect(mockFetch).toHaveBeenCalledWith("/api/shell", {
      method: "POST",
      signal: undefined,
    });
  });

  test("throws on non-ok response", async () => {
    mockFetch.mockResolvedValue({ ok: false, status: 500 });
    await expect(createShell()).rejects.toThrow("Failed to create shell: 500");
  });
});

describe("deleteShell", () => {
  test("DELETE /api/shell with keepalive", () => {
    mockFetch.mockResolvedValue({ ok: true });
    deleteShell();
    expect(mockFetch).toHaveBeenCalledWith("/api/shell", {
      method: "DELETE",
      keepalive: true,
    });
  });
});

describe("execute", () => {
  test("yields stdout and stderr events", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      ...sseBody([
        'data: {"type":"stdout","data":"hello"}',
        'data: {"type":"stderr","data":"warn"}',
        'data: {"type":"complete","exitCode":0}',
      ]),
    });

    const events = [];
    for await (const event of execute("echo hello")) {
      events.push(event);
    }

    expect(events).toEqual([
      { type: SseEventType.STDOUT, data: "hello" },
      { type: SseEventType.STDERR, data: "warn" },
      { type: SseEventType.COMPLETE, exitCode: 0 },
    ]);
  });

  test("throws on non-ok response", async () => {
    mockFetch.mockResolvedValue({ ok: false, status: 403, headers: responseHeaders() });
    const gen = execute("ls");
    await expect(gen.next()).rejects.toThrow("Failed to execute: 403");
  });

  test("throws reassigned error when response has reassigned header", async () => {
    mockFetch.mockResolvedValue({
      ok: false,
      status: 400,
      headers: responseHeaders({ "X-Session-Reassigned": "true" }),
    });
    const gen = execute("ls");
    await expect(gen.next()).rejects.toBeInstanceOf(SessionReassignedError);
  });

  test("throws on missing body", async () => {
    mockFetch.mockResolvedValue({ ok: true, headers: responseHeaders(), body: null });
    const gen = execute("ls");
    await expect(gen.next()).rejects.toThrow("No response body");
  });

  test("parses data: without trailing space", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      ...sseBody([
        'data:{"type":"stdout","data":"no-space"}',
        'data: {"type":"stdout","data":"with-space"}',
      ]),
    });

    const events = [];
    for await (const event of execute("test")) {
      events.push(event);
    }

    expect(events).toEqual([
      { type: SseEventType.STDOUT, data: "no-space" },
      { type: SseEventType.STDOUT, data: "with-space" },
    ]);
  });

  test("skips empty data: lines", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      ...sseBody(["data:", 'data: {"type":"stdout","data":"ok"}']),
    });

    const events = [];
    for await (const event of execute("test")) {
      events.push(event);
    }

    expect(events).toEqual([{ type: SseEventType.STDOUT, data: "ok" }]);
  });

  test("skips non-data lines", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      ...sseBody(["event: ping", "", 'data: {"type":"stdout","data":"ok"}']),
    });

    const events = [];
    for await (const event of execute("test")) {
      events.push(event);
    }

    expect(events).toEqual([{ type: SseEventType.STDOUT, data: "ok" }]);
  });

  test("cancels reader on early break", async () => {
    const cancelFn = vi.fn();
    const encoded = textEncoder.encode(
      'data: {"type":"stdout","data":"a"}\ndata: {"type":"stdout","data":"b"}\n',
    );
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders(),
      body: {
        getReader: () => ({
          read: async () => ({ done: false, value: encoded }),
          cancel: cancelFn,
        }),
      },
    });

    for await (const _ of execute("cmd")) {
      break;
    }

    expect(cancelFn).toHaveBeenCalled();
  });
});
