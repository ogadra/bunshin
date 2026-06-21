import { createShell, deleteShell, execute, SessionReassignedError, SseEventType } from "./client";
import "./style.css";

const status = document.getElementById("status")!;
const output = document.getElementById("output")!;
const form = document.getElementById("input-bar") as HTMLFormElement;
const input = document.getElementById("command") as HTMLInputElement;
const button = form.querySelector("button")!;

let running = false;

const append = (text: string, className?: string) => {
  if (className) {
    const span = document.createElement("span");
    span.className = className;
    span.textContent = text;
    output.appendChild(span);
  } else {
    output.appendChild(document.createTextNode(text));
  }
  output.scrollTop = output.scrollHeight;
};

const setDisabled = (disabled: boolean) => {
  input.disabled = disabled;
  button.disabled = disabled;
};

const MAX_DELAY_MS = 8000;
const ac = new AbortController();
const attempt = async (delay: number): Promise<void> => {
  try {
    await createShell(ac.signal);
    if (ac.signal.aborted) return;
    status.hidden = true;
    setDisabled(false);
    append("$ ");
    input.focus();
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") return;
    if (ac.signal.aborted) return;
    status.textContent = "Connection failed. Retrying...";
    setTimeout(() => {
      if (!ac.signal.aborted) void attempt(Math.min(delay * 2, MAX_DELAY_MS));
    }, delay);
  }
};

void attempt(1000);

window.addEventListener("beforeunload", () => {
  ac.abort();
  execAbort?.abort();
  deleteShell();
});

let execAbort: AbortController | null = null;

const run = async () => {
  const cmd = input.value.trim();
  if (!cmd || running) return;
  input.value = "";
  running = true;
  setDisabled(true);
  append(cmd + "\n");

  const controller = new AbortController();
  execAbort = controller;

  try {
    for await (const event of execute(cmd, controller.signal)) {
      switch (event.type) {
        case SseEventType.STDOUT:
          append(event.data);
          break;
        case SseEventType.STDERR:
          append(event.data, "stderr");
          break;
        case SseEventType.COMPLETE:
          if (event.exitCode !== 0) {
            append(`exit code: ${event.exitCode}\n`, "error");
          }
          break;
      }
    }
  } catch (err) {
    if (controller.signal.aborted) return;
    if (err instanceof SessionReassignedError) {
      try {
        await createShell(controller.signal);
        append("Session recreated. Run the command again.\n", "error");
      } catch (createErr) {
        const msg = createErr instanceof Error ? createErr.message : "Unknown error";
        append(`Error: ${msg}\n`, "error");
      }
      return;
    }
    const msg = err instanceof Error ? err.message : "Unknown error";
    append(`Error: ${msg}\n`, "error");
  } finally {
    if (execAbort === controller) execAbort = null;
    append("$ ");
    running = false;
    setDisabled(false);
    input.focus();
  }
};

form.addEventListener("submit", (e) => {
  e.preventDefault();
  void run();
});
