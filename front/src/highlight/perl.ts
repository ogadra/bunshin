/*
 * Tokenization logic ported from the CodeMirror legacy-modes Perl mode
 * (https://github.com/codemirror/legacy-modes/blob/main/mode/perl.js),
 * MIT License, Copyright (C) 2018-2021 by Marijn Haverbeke <marijn@haverbeke.berlin> and others.
 * See front/THIRD_PARTY_NOTICES for the full license text.
 */

import { KEYWORDS } from "./keywords";

export const TokenType = {
  PLAIN: "plain",
  COMMENT: "comment",
  STRING: "string",
  REGEXP: "regexp",
  VARIABLE: "variable",
  NUMBER: "number",
  KEYWORD: "keyword",
  FUNCTION: "function",
} as const;

export type TokenType = (typeof TokenType)[keyof typeof TokenType];

export type Token = { type: TokenType; text: string };

const NAME_KEYWORDS = new Set(["sub", "package"]);

const NUMBER_RE =
  /0x[\da-f][\da-f_]*|0b[01][01_]*|(?:\d[\d_]*)?\.\d[\d_]*(?:e[+-]?\d+)?|\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?/iy;

const WORD_RE = /[A-Za-z_]\w*(?:::\w+)*/y;

const SPECIAL_SCALAR_CHARS = "&`'+/\\,;.<>@!$?:=~^|%\"-";

// $1 / $^W / 単体の $# など、$ サジル固有の特殊スカラーの終端
export const specialScalarEnd = (code: string, pos: number): number | null => {
  const c = code[pos + 1] ?? "";
  if (/\d/.test(c)) {
    let j = pos + 2;
    while (j < code.length && /\d/.test(code[j] ?? "")) j++;
    return j;
  }
  if (c === "^" && /[A-Z]/.test(code[pos + 2] ?? "")) return pos + 3;
  if (c === "#" && !/[A-Za-z_{$]/.test(code[pos + 2] ?? "")) return pos + 2;
  return null;
};

// \w の並びを :: 連結込みで進める。${2} を許すため数字始まりをここでは拒否しない
export const wordPathEnd = (code: string, from: number): number => {
  let k = from;
  while (k < code.length && /\w/.test(code[k] ?? "")) k++;
  while (code[k] === ":" && code[k + 1] === ":" && /[A-Za-z_]/.test(code[k + 2] ?? "")) {
    k += 2;
    while (k < code.length && /\w/.test(code[k] ?? "")) k++;
  }
  return k;
};

// from は "{" の位置。${name} ${Foo::Bar} ${^NAME} と、$ に限り ${!} を受理する
export const bracedVariableEnd = (code: string, from: number, sigil: string): number | null => {
  let k = from + 1;
  if (code[k] === "^") k++;
  const end = wordPathEnd(code, k);
  if (end > k && code[end] === "}") return end + 1;
  if (end === k && sigil === "$") {
    const c = code[end] ?? "";
    if (c !== "" && SPECIAL_SCALAR_CHARS.includes(c) && code[end + 1] === "}") return end + 2;
  }
  return null;
};

const QUOTE_OPS: Record<string, { type: TokenType; parts: 1 | 2; modifiers: boolean }> = {
  q: { type: TokenType.STRING, parts: 1, modifiers: false },
  qq: { type: TokenType.STRING, parts: 1, modifiers: false },
  qw: { type: TokenType.STRING, parts: 1, modifiers: false },
  qx: { type: TokenType.STRING, parts: 1, modifiers: false },
  qr: { type: TokenType.REGEXP, parts: 1, modifiers: true },
  m: { type: TokenType.REGEXP, parts: 1, modifiers: true },
  s: { type: TokenType.REGEXP, parts: 2, modifiers: true },
  tr: { type: TokenType.REGEXP, parts: 2, modifiers: true },
  y: { type: TokenType.REGEXP, parts: 2, modifiers: true },
};

// CodeMirror perl mode と同じ限定集合。=> の = などをデリミタと誤認しないため任意の記号は許可しない
const DELIM_OPEN_RE = /[\^'"!~/([{<]/;
const PAIRED_CLOSE: Record<string, string> = { "(": ")", "[": "]", "{": "}", "<": ">" };
const AMBIGUOUS_QUOTE_OPS = new Set(["m", "s", "tr", "y"]);

const HEREDOC_RE = /<<(~?)(?:([A-Za-z_]\w*)|"([A-Za-z_]\w*)"|'([A-Za-z_]\w*)'|`([A-Za-z_]\w*)`)/y;
const POD_CUT_RE = /\n=cut(?!\w)[^\n]*/g;

export const tokenizePerl = (code: string): Token[] => {
  const tokens: Token[] = [];
  let pos = 0;
  let expectName = false;
  let prev: { type: TokenType; last: string } | null = null;
  const heredocQueue: { tag: string; indented: boolean }[] = [];

  const push = (type: TokenType, end: number): void => {
    const text = code.slice(pos, end);
    const last = tokens[tokens.length - 1];
    if (last !== undefined && last.type === type) {
      last.text += text;
    } else {
      tokens.push({ type, text });
    }
    const trimmed = text.trimEnd();
    if (type !== TokenType.COMMENT && trimmed !== "") {
      prev = { type, last: trimmed[trimmed.length - 1] ?? "" };
    }
    pos = end;
  };

  const matchAt = (re: RegExp): string | null => {
    re.lastIndex = pos;
    const m = re.exec(code);
    return m === null ? null : m[0];
  };

  // 直前のトークンから、/ がパターン開始になり得る文脈（項が来る位置）かを判定する
  const regexAllowed = (): boolean => {
    if (prev === null) return true;
    if (prev.type === TokenType.KEYWORD) return true;
    if (prev.type === TokenType.PLAIN || prev.type === TokenType.FUNCTION) {
      // 末尾 / は // や /= の演算子の一部であり、続く / はパターン開始ではない
      return !/[)\]}\w"'/]/.test(prev.last);
    }
    return false;
  };

  const quotedEnd = (quote: string): number => {
    for (let i = pos + 1; i < code.length; i++) {
      if (code[i] === "\\") i++;
      else if (code[i] === quote) return i + 1;
    }
    // null や例外を返すと編集途中の入力でハイライトが丸ごと消えるため、
    // 閉じていない引用符は末尾までを文字列とみなす
    return code.length;
  };

  const delimitedEnd = (open: string, from: number): number => {
    const close = PAIRED_CLOSE[open];
    let depth = 1;
    for (let i = from; i < code.length; i++) {
      const c = code[i];
      if (c === "\\") i++;
      else if (close !== undefined && c === open) depth++;
      else if (c === (close ?? open)) {
        depth--;
        if (depth === 0) return i + 1;
      }
    }
    return code.length;
  };

  const podEnd = (): number => {
    if (code.startsWith("=cut", pos) && !/\w/.test(code[pos + 4] ?? "")) {
      const nl = code.indexOf("\n", pos);
      return nl === -1 ? code.length : nl;
    }
    POD_CUT_RE.lastIndex = pos;
    const m = POD_CUT_RE.exec(code);
    return m === null ? code.length : m.index + m[0].length;
  };

  const heredocBodyEnd = (tag: string, indented: boolean): number => {
    for (let search = pos; ; ) {
      const nl = code.indexOf("\n", search);
      const line = code.slice(search, nl === -1 ? code.length : nl);
      if ((indented ? line.trimStart() : line) === tag) {
        return nl === -1 ? code.length : nl + 1;
      }
      if (nl === -1) return code.length;
      search = nl + 1;
    }
  };

  const variableEnd = (): number | null => {
    const sigil = code[pos] ?? "";
    let i = pos + 1;
    if (sigil === "$") {
      const special = specialScalarEnd(code, pos);
      if (special !== null) return special;
      if (code[i] === "#") i++;
    }
    let j = i;
    while (code[j] === "$") j++;
    if (code[j] === "{") {
      const braced = bracedVariableEnd(code, j, sigil);
      if (braced !== null) return braced;
    }
    if (/[A-Za-z_]/.test(code[j] ?? "")) return wordPathEnd(code, j);
    if (sigil === "$") {
      if (j > i) return i + 1;
      const c = code[i] ?? "";
      if (c !== "" && SPECIAL_SCALAR_CHARS.includes(c)) return i + 1;
    }
    return null;
  };

  while (pos < code.length) {
    const ch = code[pos] ?? "";
    const atLineStart = pos === 0 || code[pos - 1] === "\n";
    if (ch === "\n" && heredocQueue.length > 0) {
      push(TokenType.PLAIN, pos + 1);
      while (pos < code.length && heredocQueue.length > 0) {
        const h = heredocQueue.shift();
        if (h === undefined) break;
        const end = heredocBodyEnd(h.tag, h.indented);
        if (end > pos) push(TokenType.STRING, end);
      }
      continue;
    }
    if (atLineStart && ch === "=" && /[A-Za-z]/.test(code[pos + 1] ?? "")) {
      push(TokenType.COMMENT, podEnd());
      // POD もコメントと同様に空白扱いなので expectName を維持する
      continue;
    }
    if (ch === "#") {
      const nl = code.indexOf("\n", pos);
      push(TokenType.COMMENT, nl === -1 ? code.length : nl);
      // sub # note\nfoo のようにコメントは宣言と名前の間に挟めるため expectName を維持する
      continue;
    }
    if (ch === "'" || ch === '"' || ch === "`") {
      push(TokenType.STRING, quotedEnd(ch));
      expectName = false;
      continue;
    }
    if (ch === "<" && code[pos + 1] === "<") {
      HEREDOC_RE.lastIndex = pos;
      const m = HEREDOC_RE.exec(code);
      if (m !== null) {
        heredocQueue.push({ tag: m[2] ?? m[3] ?? m[4] ?? m[5] ?? "", indented: m[1] === "~" });
        push(TokenType.STRING, pos + m[0].length);
        expectName = false;
        continue;
      }
    }
    if (ch === "$" || ch === "@" || ch === "%" || ch === "&") {
      const end = variableEnd();
      if (end !== null) {
        push(TokenType.VARIABLE, end);
        expectName = false;
        continue;
      }
    }
    if (ch === "/" && regexAllowed()) {
      let end = delimitedEnd("/", pos + 1);
      while (end < code.length && /[a-z]/.test(code[end] ?? "")) end++;
      push(TokenType.REGEXP, end);
      expectName = false;
      continue;
    }
    // 範囲演算子 .. の直後の桁は先頭ドット付き小数 (.5) と解釈しない
    if (/\d/.test(ch) || (ch === "." && code[pos - 1] !== "." && /\d/.test(code[pos + 1] ?? ""))) {
      const m = matchAt(NUMBER_RE);
      if (m !== null) {
        push(TokenType.NUMBER, pos + m.length);
        expectName = false;
        continue;
      }
    }
    if (/[A-Za-z_]/.test(ch)) {
      const word = matchAt(WORD_RE) ?? ch;
      if (expectName) {
        push(TokenType.FUNCTION, pos + word.length);
        expectName = false;
        continue;
      }
      const op = QUOTE_OPS[word];
      if (op !== undefined) {
        const d = code[pos + word.length] ?? "";
        // $obj->s(...) のようなメソッド呼び出しをクォート演算子と誤認しない
        const allowed = !AMBIGUOUS_QUOTE_OPS.has(word) || (regexAllowed() && prev?.last !== ">");
        if (allowed && DELIM_OPEN_RE.test(d)) {
          let end = delimitedEnd(d, pos + word.length + 1);
          if (op.parts === 2) {
            if (PAIRED_CLOSE[d] !== undefined) {
              let j = end;
              while (j < code.length && /\s/.test(code[j] ?? "")) j++;
              const d2 = code[j] ?? "";
              if (DELIM_OPEN_RE.test(d2)) end = delimitedEnd(d2, j + 1);
            } else {
              end = delimitedEnd(d, end);
            }
          }
          if (op.modifiers) {
            while (end < code.length && /[a-z]/.test(code[end] ?? "")) end++;
          }
          push(op.type, end);
          continue;
        }
      }
      if (atLineStart && (word === "__END__" || word === "__DATA__")) {
        push(TokenType.COMMENT, code.length);
        continue;
      }
      if (KEYWORDS.has(word)) {
        push(TokenType.KEYWORD, pos + word.length);
        expectName = NAME_KEYWORDS.has(word);
      } else {
        push(TokenType.PLAIN, pos + word.length);
      }
      continue;
    }
    if (!/\s/.test(ch)) expectName = false;
    push(TokenType.PLAIN, pos + 1);
  }

  return tokens;
};
