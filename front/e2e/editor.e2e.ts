import { expect, test, type Page } from "@playwright/test";
import { samplePerl } from "../src/samplePerl";

const input = (page: Page) => page.locator(".editor-input");
const highlight = (page: Page) => page.locator(".editor-highlight");

// vite preview は SPA fallback で /api/app/handler にも index.html を返してしまうので、
// GET を明示的にモックしないと initial code が HTML になって Perl のトークン検証が壊れる。
// PUT/GET と iframe :5000 をまとめて捕まえるヘルパー
async function stubHandlerApi(page: Page, initialSource: string): Promise<{ puts: string[] }> {
  const puts: string[] = [];
  let current = initialSource;
  await page.route("**/api/app/handler", async (route, req) => {
    if (req.method() === "GET") {
      await route.fulfill({ status: 200, body: current, contentType: "text/plain" });
      return;
    }
    if (req.method() === "PUT") {
      const body = req.postData() ?? "";
      current = body;
      puts.push(body);
      await route.fulfill({ status: 204 });
      return;
    }
    await route.continue();
  });
  // iframe の :5000 は preview サーバーからは到達不能なので、任意の 200 を返して DevTools の
  // net::ERR ノイズと視覚的な壊れ表示を抑える
  await page.route("http://127.0.0.1:5000/**", async (route) => {
    await route.fulfill({ status: 200, body: current, contentType: "text/plain" });
  });
  return { puts };
}

test.beforeEach(async ({ page }) => {
  await stubHandlerApi(page, samplePerl);
  await page.goto("/");
  await highlight(page).locator("span").first().waitFor();
});

test("the editor fills the viewport and the terminal UI is absent", async ({ page }) => {
  const geometry = await page.evaluate(() => ({
    editorHeight: document.querySelector(".editor")?.getBoundingClientRect().height,
    viewportHeight: window.innerHeight,
    command: document.getElementById("command"),
    output: document.getElementById("output"),
  }));
  expect(geometry.editorHeight).toBe(geometry.viewportHeight);
  expect(geometry.command).toBeNull();
  expect(geometry.output).toBeNull();
});

test("the initial sample renders every token kind", async ({ page }) => {
  for (const kind of ["comment", "keyword", "function", "variable", "number", "string", "regexp"]) {
    await expect(highlight(page).locator(`.hl-${kind}`).first()).toBeVisible();
  }
});

test("typing re-highlights live", async ({ page }) => {
  await input(page).click();
  await page.keyboard.press("ControlOrMeta+a");
  await input(page).pressSequentially("my $greeting = qq{hello} . m|\\d+|;", { delay: 5 });
  await expect(highlight(page).locator(".hl-string")).toHaveText(["hello"]);
  await expect(highlight(page).locator(".hl-regexp")).toHaveText(["\\d+"]);
  await expect(highlight(page).locator(".hl-variable")).toHaveText(["$greeting"]);
});

test("input is rendered as text, never as markup", async ({ page }) => {
  await input(page).click();
  await page.keyboard.press("ControlOrMeta+a");
  await input(page).pressSequentially("<img src=x onerror=alert(1)>", { delay: 5 });
  await expect(highlight(page).locator("img")).toHaveCount(0);
  await expect(highlight(page)).toContainText("<img src=x onerror=alert(1)>");
});

test("Tab indents at the caret and native undo restores it", async ({ page }) => {
  await input(page).click();
  await page.keyboard.press("ControlOrMeta+Home");
  await page.keyboard.press("Tab");
  await expect(input(page)).toBeFocused();
  expect(await input(page).inputValue()).toMatch(/^ {4}/);

  await page.keyboard.press("ControlOrMeta+z");
  expect(await input(page).inputValue()).not.toMatch(/^ {4}/);
});

test("Shift+Tab keeps its backward focus move", async ({ page }) => {
  await input(page).click();
  const before = await input(page).inputValue();
  await page.keyboard.press("Shift+Tab");
  await expect(input(page)).not.toBeFocused();
  expect(await input(page).inputValue()).toBe(before);
});

test("Tab right after Escape keeps its forward focus move", async ({ page }) => {
  await input(page).click();
  const before = await input(page).inputValue();
  await page.keyboard.press("Escape");
  await page.keyboard.press("Tab");
  await expect(input(page)).not.toBeFocused();
  expect(await input(page).inputValue()).toBe(before);
});

// 縦横どちらもスクロールさせるため、長い行を大量に流し込む
const OVERFLOWING_CODE = `my $line = "${"x".repeat(500)}";\n`.repeat(200);

test("the highlight layer tracks textarea scrolling", async ({ page }) => {
  await input(page).evaluate((el: HTMLTextAreaElement, code) => {
    el.value = code;
    el.dispatchEvent(new Event("input"));
    el.scrollTop = 60;
    el.scrollLeft = 15;
    el.dispatchEvent(new Event("scroll"));
  }, OVERFLOWING_CODE);
  const scroll = await highlight(page).evaluate((el) => ({
    top: el.scrollTop,
    left: el.scrollLeft,
  }));
  expect(scroll).toEqual({ top: 60, left: 15 });
});

test("both layers lay out lines at the same vertical extent", async ({ page }) => {
  await input(page).evaluate((el: HTMLTextAreaElement, code) => {
    el.value = code;
    el.dispatchEvent(new Event("input"));
  }, OVERFLOWING_CODE);
  // 行の縦位置がずれるとキャレットと色付き文字が合わなくなるため scrollHeight の一致を確認する。
  // scrollWidth は textarea の縦スクロールバー分だけ差が出るが、各グリフの x 座標は
  // padding と scrollLeft から決まりレイヤ間で一致するので、横のずれには繋がらない
  const height = await page.evaluate(() => {
    const ta = document.querySelector<HTMLTextAreaElement>(".editor-input");
    const hl = document.querySelector<HTMLElement>(".editor-highlight");
    if (ta === null || hl === null) throw new Error("editor layers are missing");
    return [ta.scrollHeight, hl.scrollHeight];
  });
  expect(height[0]).toBe(height[1]);
});

test("both layers share identical geometry", async ({ page }) => {
  const geometry = await page.evaluate(() => {
    const hl = document.querySelector(".editor-highlight");
    const ta = document.querySelector(".editor-input");
    if (hl === null || ta === null) throw new Error("editor layers are missing");
    const a = hl.getBoundingClientRect();
    const b = ta.getBoundingClientRect();
    const ca = getComputedStyle(hl);
    const cb = getComputedStyle(ta);
    return {
      sameBox: a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height,
      font: [ca.font, cb.font],
      padding: [ca.padding, cb.padding],
    };
  });
  expect(geometry.sameBox).toBe(true);
  expect(geometry.font[0]).toBe(geometry.font[1]);
  expect(geometry.padding[0]).toBe(geometry.padding[1]);
});

test.describe("Perl HMR wiring", () => {
  // トップレベルの beforeEach でも stub は入っているが、PUT の payload を検査するには
  // このブロック用の stub インスタンスを別で取り直す必要がある。片方だけ有効になるよう
  // beforeEach を上書きして goto 前に個別 stub を仕込む
  let stub: { puts: string[] };

  test.beforeEach(async ({ page }) => {
    stub = await stubHandlerApi(page, 'sub { return (200, "text/plain", "before"); };\n');
    await page.goto("/");
    await highlight(page).locator("span").first().waitFor();
  });

  test("stopping typing PUTs the handler and reloads the iframe", async ({ page }) => {
    const initialSrc = await page.locator("#preview").getAttribute("src");

    await input(page).click();
    await page.keyboard.press("ControlOrMeta+End");
    await page.keyboard.type("\n# added by e2e", { delay: 20 });

    await expect.poll(() => stub.puts.length, { timeout: 5000 }).toBeGreaterThan(0);
    expect(stub.puts.at(-1)).toContain("# added by e2e");
    await expect
      .poll(() => page.locator("#preview").getAttribute("src"), { timeout: 5000 })
      .not.toBe(initialSrc);
  });
});
