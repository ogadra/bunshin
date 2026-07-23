import { describe, test, expect, vi, beforeEach } from "vitest";
import {
  createShell,
  deleteShell,
  execute,
  getAppHandler,
  putAppHandler,
  SseEventType,
} from "./client";
import { AppError } from "./errors/AppError";
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

const HEX = "0123456789abcdef0123456789abcdef";

const STACK = "ap-northeast-1";

const jsonErrorResponse = (status: number, body: unknown) => ({
  ok: false,
  status,
  headers: responseHeaders(),
  clone() {
    return { json: async () => body };
  },
});

describe("getAppHandler", () => {
  test("GET /api/app/handler returns text body, session hex and stack name", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({ "X-Session-Hex": HEX, "X-Stack-Name": STACK }),
      text: async () => "sub { };",
    });
    await expect(getAppHandler()).resolves.toEqual({
      source: "sub { };",
      sessionHex: HEX,
      stackName: STACK,
    });
    expect(mockFetch).toHaveBeenCalledWith("/api/app/handler");
  });

  test("throws internal error when X-Session-Hex is absent", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({ "X-Stack-Name": STACK }),
      text: async () => "sub { };",
    });
    const err = await getAppHandler().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).key).toBe("errorInternal");
  });

  test("throws internal error when X-Stack-Name is absent", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({ "X-Session-Hex": HEX }),
      text: async () => "sub { };",
    });
    const err = await getAppHandler().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).key).toBe("errorInternal");
  });

  test("throws AppError classified from response body on non-ok", async () => {
    mockFetch.mockResolvedValue(
      jsonErrorResponse(503, { code: "NO_IDLE_RUNNER", message: "no idle runner available" }),
    );
    const err = await getAppHandler().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).key).toBe("errorNoIdleRunner");
  });
});

describe("putAppHandler", () => {
  test("PUT /api/app/handler returns hex, stack, and reassigned=false by default", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({ "X-Session-Hex": HEX, "X-Stack-Name": STACK }),
    });
    await expect(putAppHandler("sub { return (200, 'text/plain', 'ok'); };")).resolves.toEqual({
      sessionHex: HEX,
      stackName: STACK,
      reassigned: false,
    });
    expect(mockFetch).toHaveBeenCalledWith("/api/app/handler", {
      method: "PUT",
      body: "sub { return (200, 'text/plain', 'ok'); };",
    });
  });

  test("reassigned is true when X-Session-Reassigned header is 'true'", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({
        "X-Session-Hex": HEX,
        "X-Stack-Name": STACK,
        "X-Session-Reassigned": "true",
      }),
    });
    await expect(putAppHandler("body")).resolves.toEqual({
      sessionHex: HEX,
      stackName: STACK,
      reassigned: true,
    });
  });

  test("throws internal error when X-Session-Hex is absent", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({ "X-Stack-Name": STACK }),
    });
    const err = await putAppHandler("body").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).key).toBe("errorInternal");
  });

  test("throws internal error when X-Stack-Name is absent", async () => {
    mockFetch.mockResolvedValue({
      ok: true,
      headers: responseHeaders({ "X-Session-Hex": HEX }),
    });
    const err = await putAppHandler("body").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).key).toBe("errorInternal");
  });

  test("throws AppError classified from runner body-too-large error", async () => {
    mockFetch.mockResolvedValue(
      jsonErrorResponse(400, { error: "read body: http: request body too large" }),
    );
    const err = await putAppHandler("body").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((err as AppError).key).toBe("errorEditTooLarge");
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
