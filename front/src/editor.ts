import { TokenType, tokenizePerl } from "./highlight/perl";

export const createPerlEditor = (container: HTMLElement, initialCode: string): void => {
  const highlight = document.createElement("pre");
  highlight.className = "editor-highlight";
  highlight.setAttribute("aria-hidden", "true");

  const input = document.createElement("textarea");
  input.className = "editor-input";
  input.spellcheck = false;
  input.wrap = "off";
  // モバイルの自動大文字化・自動修正はコードを構文レベルで書き換える
  // (sub → Sub 等)。spellcheck=false だけでは autocorrect は止まらない
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("autocorrect", "off");
  input.setAttribute("aria-label", "Perl code");
  input.value = initialCode;

  const render = (): void => {
    const nodes = tokenizePerl(input.value).map((token) => {
      if (token.type === TokenType.PLAIN) return document.createTextNode(token.text);
      const span = document.createElement("span");
      span.className = `hl-${token.type}`;
      span.textContent = token.text;
      return span;
    });
    // 入力が改行で終わると <pre> は末尾の改行を描画せず1行分低くなり
    // キャレット位置とずれるため、番兵の改行を常に足す
    highlight.replaceChildren(...nodes, document.createTextNode("\n"));
  };

  const syncScroll = (): void => {
    highlight.scrollTop = input.scrollTop;
    highlight.scrollLeft = input.scrollLeft;
  };

  input.addEventListener("input", render);
  input.addEventListener("scroll", syncScroll);

  render();
  container.append(highlight, input);
};
