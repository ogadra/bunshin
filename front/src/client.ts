import { SessionReassignedError } from "./errors/SessionReassignedError";

export const SseEventType = {
  STDOUT: "stdout",
  STDERR: "stderr",
  COMPLETE: "complete",
} as const;

export type SseEvent =
  | { type: typeof SseEventType.STDOUT; data: string }
  | { type: typeof SseEventType.STDERR; data: string }
  | { type: typeof SseEventType.COMPLETE; exitCode: number };

export const createShell = async (signal?: AbortSignal): Promise<void> => {
  const res = await fetch("/api/shell", { method: "POST", signal });
  if (!res.ok) throw new Error(`Failed to create shell: ${res.status}`);
};

export const deleteShell = (): void => {
  void fetch("/api/shell", { method: "DELETE", keepalive: true }).catch((err: unknown) => {
    console.error("Failed to delete shell", err);
  });
};

export async function* execute(command: string, signal?: AbortSignal): AsyncGenerator<SseEvent> {
  const res = await fetch("/api/execute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command }),
    signal,
  });
  if (res.headers.get("X-Session-Reassigned") === "true") {
    throw new SessionReassignedError();
  }
  if (!res.ok) throw new Error(`Failed to execute: ${res.status}`);
  if (!res.body) throw new Error("No response body");

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  const chunks: string[] = [];
  let completed = false;

  try {
    for (;;) {
      const { done, value } = await reader.read();
      chunks.push(done ? decoder.decode() : decoder.decode(value, { stream: true }));

      const lines = chunks.join("").split("\n");
      chunks.length = 0;
      if (!done) chunks.push(lines.pop()!);

      for (const line of lines) {
        if (!line.startsWith("data:")) continue;
        const payload = line.slice(5).trimStart();
        if (!payload) continue;
        yield JSON.parse(payload) as SseEvent;
      }

      if (done) {
        completed = true;
        break;
      }
    }
  } finally {
    if (!completed) {
      await reader.cancel();
    }
  }
}
