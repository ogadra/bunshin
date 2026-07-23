import { expect, test, type Page } from "@playwright/test";
import { samplePerl } from "../src/samplePerl";

const input = (page: Page) => page.locator(".editor-input");
const highlight = (page: Page) => page.locator(".editor-highlight");

// nginxが/api応答に付けるX-Session-Hexを模したテスト用のhex
const E2E_SESSION_HEX = "0123456789abcdef0123456789abcdef";

// brokerが/api応答に付けるX-Stack-Nameを模したテスト用のstack
const E2E_STACK_NAME = "preview";

// vite previewはSPA fallbackで/api/app/handlerにもindex.htmlを返してしまうので、
// GETを明示的にモックしないとinitial codeがHTMLになってPerlのトークン検証が壊れる。
// PUT/GETとiframe preview先をまとめて捕まえるヘルパー
async function stubHandlerApi(page: Page, initialSource: string): Promise<{ puts: string[] }> {
  const puts: string[] = [];
  let current = initialSource;
  const apiHeaders = {
    "X-Session-Hex": E2E_SESSION_HEX,
    "X-Stack-Name": E2E_STACK_NAME,
  };
  await page.route("**/api/app/handler", async (route, req) => {
    if (req.method() === "GET") {
      await route.fulfill({
        status: 200,
        body: current,
        contentType: "text/plain",
        headers: apiHeaders,
      });
      return;
    }
    if (req.method() === "PUT") {
      const body = req.postData() ?? "";
      current = body;
      puts.push(body);
      await route.fulfill({ status: 204, headers: apiHeaders });
      return;
    }
    await route.continue();
  });
  // preview先ドメインはpreviewサーバーからは到達不能なので、任意の200を返してDevToolsの
  // net::ERRノイズと視覚的な壊れ表示を抑える。webServer.envのVITE_PERL_ORIGIN_TEMPLATEと揃える
  await page.route("http://*.preview.test/**", async (route) => {
    await route.fulfill({ status: 200, body: current, contentType: "text/plain" });
  });
  return { puts };
}

let handlerStub: { puts: string[] };

test.beforeEach(async ({ page }) => {
  handlerStub = await stubHandlerApi(page, samplePerl);
  await page.goto("/");
  await highlight(page).locator("span").first().waitFor();
});

test("no terminal UI is present", async ({ page }) => {
  const dom = await page.evaluate(() => ({
    command: document.getElementById("command"),
    output: document.getElementById("output"),
  }));
  expect(dom.command).toBeNull();
  expect(dom.output).toBeNull();
});

const paneGeometry = (page: Page) =>
  page.evaluate(() => ({
    editorRect: document.querySelector(".editor")?.getBoundingClientRect(),
    previewRect: document.querySelector(".preview")?.getBoundingClientRect(),
    viewportWidth: window.innerWidth,
    viewportHeight: window.innerHeight,
  }));

test.describe("landscape viewport", () => {
  test.use({ viewport: { width: 1280, height: 720 } });

  test("splits the panes side-by-side", async ({ page }) => {
    const g = await paneGeometry(page);
    if (g.editorRect === undefined || g.previewRect === undefined)
      throw new Error("panes are missing");
    expect(g.editorRect.height).toBe(g.viewportHeight);
    expect(g.previewRect.height).toBe(g.viewportHeight);
    expect(g.editorRect.left).toBe(0);
    expect(g.previewRect.left).toBeGreaterThan(g.editorRect.left);
    expect(g.editorRect.width + g.previewRect.width).toBe(g.viewportWidth);
  });
});

test.describe("portrait viewport", () => {
  test.use({ viewport: { width: 480, height: 900 } });

  test("stacks the panes vertically", async ({ page }) => {
    const g = await paneGeometry(page);
    if (g.editorRect === undefined || g.previewRect === undefined)
      throw new Error("panes are missing");
    expect(g.editorRect.width).toBe(g.viewportWidth);
    expect(g.previewRect.width).toBe(g.viewportWidth);
    expect(g.editorRect.top).toBe(0);
    expect(g.previewRect.top).toBeGreaterThan(g.editorRect.top);
    expect(g.editorRect.height + g.previewRect.height).toBe(g.viewportHeight);
  });
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

// 折り返しモードでも縦スクロールと折り返し高さの検証ができるだけの分量を流し込む
const OVERFLOWING_CODE = `my $line = "${"x".repeat(500)}";\n`.repeat(200);

test("the highlight layer tracks textarea scrolling", async ({ page }) => {
  await input(page).evaluate((el: HTMLTextAreaElement, code) => {
    el.value = code;
    el.dispatchEvent(new Event("input"));
    el.scrollTop = 60;
    el.dispatchEvent(new Event("scroll"));
  }, OVERFLOWING_CODE);
  const scrollTop = await highlight(page).evaluate((el) => el.scrollTop);
  expect(scrollTop).toBe(60);
});

test("both layers lay out lines at the same vertical extent", async ({ page }) => {
  await input(page).evaluate((el: HTMLTextAreaElement, code) => {
    el.value = code;
    el.dispatchEvent(new Event("input"));
  }, OVERFLOWING_CODE);
  // 折り返し位置がずれるとキャレットと色付き文字が合わなくなる。
  // scrollHeight の一致で両レイヤが同じ幅で折り返していることを確認する
  const height = await page.evaluate(() => {
    const ta = document.querySelector<HTMLTextAreaElement>(".editor-input");
    const hl = document.querySelector<HTMLElement>(".editor-highlight");
    if (ta === null || hl === null) throw new Error("editor layers are missing");
    return [ta.scrollHeight, hl.scrollHeight];
  });
  expect(height[0]).toBe(height[1]);
});

test("wrap keeps both layers within their client width", async ({ page }) => {
  await input(page).evaluate((el: HTMLTextAreaElement, code) => {
    el.value = code;
    el.dispatchEvent(new Event("input"));
  }, OVERFLOWING_CODE);
  const overflow = await page.evaluate(() => {
    const ta = document.querySelector<HTMLTextAreaElement>(".editor-input");
    const hl = document.querySelector<HTMLElement>(".editor-highlight");
    if (ta === null || hl === null) throw new Error("editor layers are missing");
    return {
      input: ta.scrollWidth - ta.clientWidth,
      highlight: hl.scrollWidth - hl.clientWidth,
    };
  });
  expect(overflow.input).toBeLessThanOrEqual(0);
  expect(overflow.highlight).toBeLessThanOrEqual(0);
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
  test("stopping typing PUTs the handler and reloads the iframe", async ({ page }) => {
    const initialSrc = await page.locator("#preview").getAttribute("src");

    await input(page).click();
    await page.keyboard.press("ControlOrMeta+End");
    await page.keyboard.type("\n# added by e2e", { delay: 20 });

    await expect.poll(() => handlerStub.puts.length, { timeout: 5000 }).toBeGreaterThan(0);
    expect(handlerStub.puts.at(-1)).toContain("# added by e2e");
    await expect
      .poll(() => page.locator("#preview").getAttribute("src"), { timeout: 5000 })
      .not.toBe(initialSrc);
  });

  test("PUT response's new X-Session-Hex / X-Stack-Name switches subsequent iframe preview URL", async ({
    page,
  }) => {
    const REASSIGNED_HEX = "fedcba9876543210fedcba9876543210";
    const REASSIGNED_STACK = "reassigned-stack";
    // beforeEachのPUT stubを、再割当てで別hex/stackが返る挙動に上書きする。
    // GETはfallthroughで元stub。
    await page.route("**/api/app/handler", async (route, req) => {
      if (req.method() !== "PUT") {
        await route.fallback();
        return;
      }
      await route.fulfill({
        status: 204,
        headers: {
          "X-Session-Hex": REASSIGNED_HEX,
          "X-Stack-Name": REASSIGNED_STACK,
        },
      });
    });
    // 新hex/stackで組み立てられるpreview先も200を返すようにしておく。
    // webServer.envの`VITE_PERL_ORIGIN_TEMPLATE=http://{hex}.{stack}.test/`と揃える。
    await page.route(`http://${REASSIGNED_HEX}.${REASSIGNED_STACK}.test/**`, async (route) => {
      await route.fulfill({ status: 200, body: "reassigned", contentType: "text/plain" });
    });

    await input(page).click();
    await page.keyboard.press("ControlOrMeta+End");
    await page.keyboard.type("\n# trigger PUT", { delay: 20 });

    await expect
      .poll(() => page.locator("#preview").getAttribute("src"), { timeout: 5000 })
      .toMatch(new RegExp(`^http://${REASSIGNED_HEX}\\.${REASSIGNED_STACK}\\.test/`));
  });

  test("edits arriving during a slow PUT wait for DEBOUNCE_MS of idle before the next PUT starts", async ({
    page,
  }) => {
    const PUT_LATENCY_MS = 2000;
    const DEBOUNCE_MS = 1000;
    const startTimes: number[] = [];
    const completeTimes: number[] = [];
    const putPayloads: string[] = [];
    // beforeEachのPUT stubを意図的な遅延つきに上書きし、GETは元のstubにfallbackで委譲する
    await page.route("**/api/app/handler", async (route, req) => {
      if (req.method() !== "PUT") {
        await route.fallback();
        return;
      }
      startTimes.push(Date.now());
      putPayloads.push(req.postData() ?? "");
      await new Promise((r) => setTimeout(r, PUT_LATENCY_MS));
      completeTimes.push(Date.now());
      await route.fulfill({
        status: 204,
        headers: {
          "X-Session-Hex": E2E_SESSION_HEX,
          "X-Stack-Name": E2E_STACK_NAME,
        },
      });
    });

    await input(page).click();
    await page.keyboard.press("ControlOrMeta+End");
    await page.keyboard.type("\n# first", { delay: 5 });
    await expect.poll(() => startTimes.length, { timeout: 3000 }).toBe(1);
    await page.keyboard.type("\n# second", { delay: 5 });
    await expect.poll(() => startTimes.length, { timeout: 8000 }).toBe(2);
    await expect.poll(() => completeTimes.length, { timeout: 5000 }).toBe(2);

    // idle契約: 1st PUT完了直後にunsent変更が残っていても、DEBOUNCE_MS経つまで2nd PUTを出さない
    const gapMs = startTimes[1] - completeTimes[0];
    expect(gapMs).toBeGreaterThanOrEqual(800);

    // 収束契約: 2nd PUTは最新スナップショットを送信し、以降は追加PUTを出さない
    expect(putPayloads.at(-1)).toContain("# second");
    await page.waitForTimeout(DEBOUNCE_MS * 2 + 200);
    expect(startTimes).toHaveLength(2);
  });
});
