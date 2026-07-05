import { expect, test, type Page } from "@playwright/test";

const input = (page: Page) => page.locator(".editor-input");
const highlight = (page: Page) => page.locator(".editor-highlight");

test.beforeEach(async ({ page }) => {
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

test("the highlight layer tracks textarea scrolling", async ({ page }) => {
  const scroll = await page.evaluate(() => {
    const el = document.querySelector<HTMLTextAreaElement>(".editor-input");
    if (el === null) throw new Error(".editor-input is missing");
    // 縦横ともに確実にオーバーフローさせてからスクロールする
    el.value = `my $line = "${"x".repeat(500)}";\n`.repeat(200);
    el.dispatchEvent(new Event("input"));
    el.scrollTop = 60;
    el.scrollLeft = 15;
    el.dispatchEvent(new Event("scroll"));
    const hl = document.querySelector<HTMLElement>(".editor-highlight");
    if (hl === null) throw new Error(".editor-highlight is missing");
    return { top: hl.scrollTop, left: hl.scrollLeft };
  });
  expect(scroll).toEqual({ top: 60, left: 15 });
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
