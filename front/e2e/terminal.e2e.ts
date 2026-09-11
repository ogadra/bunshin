import { expect, test, type Page } from "@playwright/test";

const command = (page: Page) => page.locator("#command");
const status = (page: Page) => page.locator("#status");
const screen = (page: Page) => page.locator(".xterm-screen");

const sse = (events: unknown[]): string =>
  events.map((event) => `data: ${JSON.stringify(event)}\n\n`).join("");

/** Accepts the shell creation and answers /api/execute with the given SSE events. */
async function stubRunner(page: Page, events: unknown[]): Promise<{ commands: string[] }> {
  const commands: string[] = [];
  await page.route("**/api/shell", async (route) => {
    await route.fulfill({ status: 204 });
  });
  await page.route("**/api/execute", async (route, req) => {
    commands.push(JSON.parse(req.postData() ?? "{}").command);
    await route.fulfill({
      status: 200,
      contentType: "text/event-stream",
      body: sse(events),
    });
  });
  return { commands };
}

const run = async (page: Page, text: string): Promise<void> => {
  await command(page).fill(text);
  await command(page).press("Enter");
};

test("the prompt appears and the input is enabled once the shell is created", async ({ page }) => {
  await stubRunner(page, []);
  await page.goto("/");

  await expect(command(page)).toBeEnabled();
  await expect(status(page)).toBeHidden();
  await expect(screen(page)).toContainText("$");
});

test("no editor UI is present", async ({ page }) => {
  await stubRunner(page, []);
  await page.goto("/");

  const dom = await page.evaluate(() => ({
    editor: document.getElementById("editor"),
    preview: document.getElementById("preview"),
    stackInfo: document.getElementById("stack-info-button"),
  }));
  expect(dom.editor).toBeNull();
  expect(dom.preview).toBeNull();
  expect(dom.stackInfo).toBeNull();
});

test("stdout is echoed into the terminal", async ({ page }) => {
  const stub = await stubRunner(page, [
    { type: "stdout", data: "2026-09-12\n" },
    { type: "complete", exitCode: 0 },
  ]);
  await page.goto("/");
  await expect(command(page)).toBeEnabled();

  await run(page, "date");

  await expect(screen(page)).toContainText("date");
  await expect(screen(page)).toContainText("2026-09-12");
  expect(stub.commands).toEqual(["date"]);
});

test("a non-zero exit code is reported", async ({ page }) => {
  await stubRunner(page, [
    { type: "stderr", data: "not found\n" },
    { type: "complete", exitCode: 127 },
  ]);
  await page.goto("/");
  await expect(command(page)).toBeEnabled();

  await run(page, "nope");

  await expect(screen(page)).toContainText("not found");
  await expect(screen(page)).toContainText("exit code: 127");
});

test("ANSI colour from the command survives into the DOM", async ({ page }) => {
  await stubRunner(page, [
    { type: "stdout", data: "[38;5;198mNix[39m\n" },
    { type: "complete", exitCode: 0 },
  ]);
  await page.goto("/");
  await expect(command(page)).toBeEnabled();

  await run(page, "lolcat");

  // lolcat と pokemonsay は 256 色を使う。
  // xterm が色付きの span を起こすことを確認する
  await expect(screen(page).locator("span.xterm-fg-198").first()).toHaveText("Nix");
});

test("the arrow keys recall the previous command", async ({ page }) => {
  await stubRunner(page, [{ type: "complete", exitCode: 0 }]);
  await page.goto("/");
  await expect(command(page)).toBeEnabled();

  await run(page, "whoami");
  await expect(command(page)).toBeEnabled();

  await command(page).press("ArrowUp");
  await expect(command(page)).toHaveValue("whoami");
  await command(page).press("ArrowDown");
  await expect(command(page)).toHaveValue("");
});

test.describe("shell creation failure", () => {
  test.use({ locale: "ja" });

  test("keeps the status visible with the Japanese reason", async ({ page }) => {
    await page.route("**/api/shell", async (route) => {
      await route.fulfill({
        status: 503,
        contentType: "application/json",
        body: JSON.stringify({ code: "NO_IDLE_RUNNER" }),
      });
    });
    await page.goto("/");

    await expect(status(page)).toContainText("実行環境に空きがありません");
    await expect(command(page)).toBeDisabled();
  });
});

test.describe("session reassignment", () => {
  test.use({ locale: "en-US" });

  test("recreates the shell and asks the user to retry", async ({ page }) => {
    await page.route("**/api/shell", async (route) => {
      await route.fulfill({ status: 204 });
    });
    await page.route("**/api/execute", async (route) => {
      await route.fulfill({
        status: 400,
        headers: { "X-Session-Reassigned": "true" },
        contentType: "application/json",
        body: JSON.stringify({ code: "SESSION_NOT_FOUND" }),
      });
    });
    await page.goto("/");
    await expect(command(page)).toBeEnabled();

    await run(page, "date");

    await expect(screen(page)).toContainText("Session recreated");
  });
});
