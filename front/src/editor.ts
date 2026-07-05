import { TokenType, tokenizePerl } from "./highlight/perl";

const INDENT = "    ";

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
    // 引数展開 (...nodes) は巨大入力でエンジンの引数上限に当たるため fragment に逐次 append する
    const fragment = document.createDocumentFragment();
    for (const token of tokenizePerl(input.value)) {
      if (token.type === TokenType.PLAIN) {
        fragment.appendChild(document.createTextNode(token.text));
      } else {
        const span = document.createElement("span");
        span.className = `hl-${token.type}`;
        span.textContent = token.text;
        fragment.appendChild(span);
      }
    }
    // 入力が改行で終わると <pre> は末尾の改行を描画せず1行分低くなり
    // キャレット位置とずれるため、番兵の改行を常に足す
    fragment.appendChild(document.createTextNode("\n"));
    highlight.replaceChildren(fragment);
  };

  const syncScroll = (): void => {
    highlight.scrollTop = input.scrollTop;
    highlight.scrollLeft = input.scrollLeft;
  };

  const insertIndent = (): void => {
    // execCommand は非推奨だが textarea のネイティブ undo 履歴を保てる唯一の手段。
    // 使えない環境では undo 履歴を諦めて値を直接書き換える
    if (document.execCommand?.("insertText", false, INDENT)) return;
    const start = input.selectionStart ?? input.value.length;
    const end = input.selectionEnd ?? start;
    input.value = input.value.slice(0, start) + INDENT + input.value.slice(end);
    input.selectionStart = input.selectionEnd = start + INDENT.length;
    input.dispatchEvent(new Event("input"));
  };

  // Tab をインデントに使う分、キーボードトラップにならないよう
  // Shift+Tab（後方）と Escape 直後の Tab（前方）はフォーカス移動のまま残す
  let tabMovesFocus = false;
  input.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      tabMovesFocus = true;
      return;
    }
    if (e.key === "Tab" && !e.shiftKey && !tabMovesFocus) {
      e.preventDefault();
      insertIndent();
    }
    tabMovesFocus = false;
  });

  input.addEventListener("input", render);
  input.addEventListener("scroll", syncScroll);

  render();
  container.append(highlight, input);
};
