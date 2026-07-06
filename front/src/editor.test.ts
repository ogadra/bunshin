// @vitest-environment happy-dom
import { describe, test, expect } from "vitest";
import { createPerlEditor } from "./editor";

const setup = (code: string) => {
  const container = document.createElement("div");
  createPerlEditor(container, code);
  const highlight = container.querySelector("pre.editor-highlight") as HTMLPreElement;
  const input = container.querySelector("textarea.editor-input") as HTMLTextAreaElement;
  return { container, highlight, input };
};

const type = (input: HTMLTextAreaElement, value: string) => {
  input.value = value;
  input.dispatchEvent(new Event("input"));
};

describe("createPerlEditor", () => {
  test("mounts a highlight layer and an editable textarea", () => {
    const { highlight, input } = setup("");
    expect(highlight).not.toBeNull();
    expect(input).not.toBeNull();
    expect(highlight.getAttribute("aria-hidden")).toBe("true");
  });

  test("the initial code appears in both layers", () => {
    const { highlight, input } = setup("my $x;");
    expect(input.value).toBe("my $x;");
    expect(highlight.textContent).toBe("my $x;\n");
  });

  test("tokens render as hl- classed spans", () => {
    const { highlight } = setup('my $x = "hi"; # note');
    expect(highlight.querySelector(".hl-keyword")?.textContent).toBe("my");
    expect(highlight.querySelector(".hl-variable")?.textContent).toBe("$x");
    expect(highlight.querySelector(".hl-string")?.textContent).toBe('"hi"');
    expect(highlight.querySelector(".hl-comment")?.textContent).toBe("# note");
  });

  test("an input event re-renders the highlight", () => {
    const { highlight, input } = setup("");
    type(input, "print 42;");
    expect(highlight.querySelector(".hl-keyword")?.textContent).toBe("print");
    expect(highlight.querySelector(".hl-number")?.textContent).toBe("42");
    type(input, "");
    expect(highlight.querySelector(".hl-keyword")).toBeNull();
  });

  test("code is rendered as text, never as markup", () => {
    const { highlight, input } = setup("");
    type(input, '<img src=x onerror=alert(1)> & "<script>"');
    expect(highlight.querySelector("img")).toBeNull();
    expect(highlight.querySelector("script")).toBeNull();
    expect(highlight.textContent).toBe('<img src=x onerror=alert(1)> & "<script>"\n');
  });

  test("a sentinel newline keeps a trailing empty line in the highlight", () => {
    const { highlight } = setup("my $x;\n");
    expect(highlight.textContent).toBe("my $x;\n\n");
  });

  test("scrolling the textarea syncs the highlight", () => {
    const { highlight, input } = setup("line\n".repeat(100));
    input.scrollTop = 40;
    input.scrollLeft = 12;
    input.dispatchEvent(new Event("scroll"));
    expect(highlight.scrollTop).toBe(40);
    expect(highlight.scrollLeft).toBe(12);
  });

  test("mobile rewriting features are disabled", () => {
    const { input } = setup("");
    expect(input.getAttribute("autocapitalize")).toBe("off");
    expect(input.getAttribute("autocorrect")).toBe("off");
    expect(input.spellcheck).toBe(false);
    expect(input.wrap).toBe("off");
  });
});

describe("Tab handling", () => {
  const pressKey = (input: HTMLTextAreaElement, key: string, shiftKey = false): KeyboardEvent => {
    const event = new KeyboardEvent("keydown", { key, shiftKey, cancelable: true });
    input.dispatchEvent(event);
    return event;
  };

  test("Tab inserts an indent at the caret instead of moving focus", () => {
    const { highlight, input } = setup("my $x;");
    input.selectionStart = input.selectionEnd = 0;
    const event = pressKey(input, "Tab");
    expect(event.defaultPrevented).toBe(true);
    expect(input.value).toBe("    my $x;");
    expect(input.selectionStart).toBe(4);
    expect(highlight.textContent).toBe("    my $x;\n");
  });

  test("Tab replaces the selected range", () => {
    const { input } = setup("abcdef");
    input.selectionStart = 1;
    input.selectionEnd = 5;
    pressKey(input, "Tab");
    expect(input.value).toBe("a    f");
  });

  test("Shift+Tab keeps its focus-moving default", () => {
    const { input } = setup("my $x;");
    const event = pressKey(input, "Tab", true);
    expect(event.defaultPrevented).toBe(false);
    expect(input.value).toBe("my $x;");
  });

  test("Tab right after Escape keeps its focus-moving default", () => {
    const { input } = setup("my $x;");
    pressKey(input, "Escape");
    const event = pressKey(input, "Tab");
    expect(event.defaultPrevented).toBe(false);
    expect(input.value).toBe("my $x;");
  });

  test("the Escape bypass lasts only for the next key", () => {
    const { input } = setup("");
    pressKey(input, "Escape");
    pressKey(input, "a");
    const event = pressKey(input, "Tab");
    expect(event.defaultPrevented).toBe(true);
    expect(input.value).toBe("    ");
  });
});
