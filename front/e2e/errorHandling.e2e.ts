import { expect, test, type Page, type Route } from "@playwright/test";
import { samplePerl } from "../src/samplePerl";

const E2E_SESSION_HEX = "0123456789abcdef0123456789abcdef";
const E2E_STACK_NAME = "preview";

const apiHeaders = {
  "X-Session-Hex": E2E_SESSION_HEX,
  "X-Stack-Name": E2E_STACK_NAME,
};

const banner = (page: Page) => page.locator(".error-banner");
const indicator = (page: Page) => page.locator(".status-indicator");
const input = (page: Page) => page.locator(".editor-input");

type PutHandler = (route: Route) => Promise<void>;

const okPut: PutHandler = async (route) => {
  await route.fulfill({ status: 204, headers: apiHeaders });
};

async function stubHandlerApi(page: Page, put: PutHandler): Promise<void> {
  await page.route("**/api/app/handler", async (route, req) => {
    if (req.method() === "GET") {
      await route.fulfill({
        status: 200,
        body: samplePerl,
        contentType: "text/plain",
        headers: apiHeaders,
      });
      return;
    }
    if (req.method() === "PUT") {
      await put(route);
      return;
    }
    await route.continue();
  });
  await page.route("http://*.preview.test/**", async (route) => {
    await route.fulfill({ status: 200, body: "", contentType: "text/plain" });
  });
}

async function stubGetFails(page: Page, status: number, body: unknown): Promise<void> {
  await page.route("**/api/app/handler", async (route, req) => {
    if (req.method() === "GET") {
      await route.fulfill({
        status,
        body: JSON.stringify(body),
        contentType: "application/json",
      });
      return;
    }
    await route.continue();
  });
}

async function typeAppend(page: Page, text: string): Promise<void> {
  await input(page).click();
  await page.keyboard.press("ControlOrMeta+End");
  await page.keyboard.type(text, { delay: 20 });
}

test.describe("bootstrap error → banner (ja UA)", () => {
  test.use({ locale: "ja" });

  test("shows Japanese message for 503 NO_IDLE_RUNNER", async ({ page }) => {
    await stubGetFails(page, 503, { code: "NO_IDLE_RUNNER", message: "no idle runner available" });
    await page.goto("/");
    await expect(banner(page)).toBeVisible();
    await expect(banner(page)).toHaveText("実行環境に空きがありません");
  });

  test("shows Japanese message for 404 SESSION_NOT_FOUND", async ({ page }) => {
    await stubGetFails(page, 404, { code: "SESSION_NOT_FOUND", message: "session not found" });
    await page.goto("/");
    await expect(banner(page)).toHaveText("以前実行した環境が見つかりません");
  });

  test("shows Japanese message for 504 GATEWAY_TIMEOUT", async ({ page }) => {
    await stubGetFails(page, 504, { code: "GATEWAY_TIMEOUT", message: "Upstream timeout." });
    await page.goto("/");
    await expect(banner(page)).toHaveText("サーバー応答がタイムアウトしました");
  });
});

test.describe("bootstrap error → banner (en UA)", () => {
  test.use({ locale: "en-US" });

  test("503 NO_IDLE_RUNNER shows English message", async ({ page }) => {
    await stubGetFails(page, 503, { code: "NO_IDLE_RUNNER", message: "no idle runner available" });
    await page.goto("/");
    await expect(banner(page)).toHaveText("No available execution environment");
  });
});

test.describe("save status indicator", () => {
  test.use({ locale: "en-US" });

  test("shows Saved after a successful PUT", async ({ page }) => {
    await stubHandlerApi(page, okPut);
    await page.goto("/");
    await page.locator(".editor-highlight span").first().waitFor();

    await typeAppend(page, "\n# trigger save");

    await expect(indicator(page)).toHaveAttribute("data-status", "saved");
    await expect(indicator(page)).toHaveText("Saved");
  });

  test("shows Error and banner when PUT fails with 503", async ({ page }) => {
    await stubHandlerApi(page, async (route) => {
      await route.fulfill({
        status: 503,
        body: JSON.stringify({ code: "NO_IDLE_RUNNER" }),
        contentType: "application/json",
      });
    });

    await page.goto("/");
    await page.locator(".editor-highlight span").first().waitFor();

    await typeAppend(page, "\n# trigger fail");

    await expect(indicator(page)).toHaveAttribute("data-status", "error");
    await expect(banner(page)).toHaveText("No available execution environment");
  });

  test("shows session-lost banner when PUT response carries X-Session-Reassigned", async ({
    page,
  }) => {
    await stubHandlerApi(page, async (route) => {
      await route.fulfill({
        status: 204,
        headers: { ...apiHeaders, "X-Session-Reassigned": "true" },
      });
    });

    await page.goto("/");
    await page.locator(".editor-highlight span").first().waitFor();

    await typeAppend(page, "\n# trigger reassign");

    await expect(banner(page)).toHaveText("Previous execution environment was not found");
    await expect(indicator(page)).toHaveAttribute("data-status", "saved");
  });
});
