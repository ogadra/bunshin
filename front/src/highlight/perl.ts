/*
 * Tokenization logic ported from the CodeMirror legacy-modes Perl mode
 * (https://github.com/codemirror/legacy-modes/blob/main/mode/perl.js),
 * MIT License, Copyright (C) 2018-2021 by Marijn Haverbeke <marijn@haverbeke.berlin> and others.
 *
 * Keyword list derived from highlight.js src/languages/perl.js
 * (https://github.com/highlightjs/highlight.js/blob/main/src/languages/perl.js),
 * BSD 3-Clause License, Copyright (c) 2006, Ivan Sagalaev. All rights reserved.
 */

export const TokenType = {
  PLAIN: "plain",
  COMMENT: "comment",
  STRING: "string",
  VARIABLE: "variable",
  NUMBER: "number",
  KEYWORD: "keyword",
  FUNCTION: "function",
} as const;

export type TokenType = (typeof TokenType)[keyof typeof TokenType];

export type Token = { type: TokenType; text: string };

// prettier-ignore
const KEYWORDS = new Set([
  "abs", "accept", "alarm", "and", "atan2", "bind", "binmode", "bless", "break",
  "caller", "chdir", "chmod", "chomp", "chop", "chown", "chr", "chroot", "class",
  "close", "closedir", "cmp", "connect", "continue", "cos", "crypt", "dbmclose",
  "dbmopen", "defined", "delete", "die", "do", "dump", "each", "else", "elsif",
  "endgrent", "endhostent", "endnetent", "endprotoent", "endpwent", "endservent",
  "eof", "eq", "eval", "exec", "exists", "exit", "exp", "fcntl", "field",
  "fileno", "flock", "for", "foreach", "fork", "format", "formline", "ge",
  "getc", "getgrent", "getgrgid", "getgrnam", "gethostbyaddr", "gethostbyname",
  "gethostent", "getlogin", "getnetbyaddr", "getnetbyname", "getnetent",
  "getpeername", "getpgrp", "getpriority", "getprotobyname", "getprotobynumber",
  "getprotoent", "getpwent", "getpwnam", "getpwuid", "getservbyname",
  "getservbyport", "getservent", "getsockname", "getsockopt", "given", "glob",
  "gmtime", "goto", "grep", "gt", "hex", "if", "index", "int", "ioctl", "join",
  "keys", "kill", "last", "lc", "lcfirst", "le", "length", "link", "listen",
  "local", "localtime", "log", "lstat", "lt", "map", "method", "mkdir",
  "msgctl", "msgget", "msgrcv", "msgsnd", "my", "ne", "next", "no", "not",
  "oct", "open", "opendir", "or", "ord", "our", "pack", "package", "pipe",
  "pop", "pos", "print", "printf", "prototype", "push", "q", "qq", "quotemeta",
  "qw", "qx", "rand", "read", "readdir", "readline", "readlink", "readpipe",
  "recv", "redo", "ref", "rename", "require", "reset", "return", "reverse",
  "rewinddir", "rindex", "rmdir", "say", "scalar", "seek", "seekdir", "select",
  "semctl", "semget", "semop", "send", "setgrent", "sethostent", "setnetent",
  "setpgrp", "setpriority", "setprotoent", "setpwent", "setservent",
  "setsockopt", "shift", "shmctl", "shmget", "shmread", "shmwrite", "shutdown",
  "sin", "sleep", "socket", "socketpair", "sort", "splice", "split", "sprintf",
  "sqrt", "srand", "stat", "state", "study", "sub", "substr", "symlink",
  "syscall", "sysopen", "sysread", "sysseek", "system", "syswrite", "tell",
  "telldir", "tie", "tied", "time", "times", "tr", "truncate", "uc", "ucfirst",
  "umask", "undef", "unless", "unlink", "unpack", "unshift", "untie", "until",
  "use", "utime", "values", "vec", "wait", "waitpid", "wantarray", "warn",
  "when", "while", "write", "x", "xor", "y",
]);

const NAME_KEYWORDS = new Set(["sub", "package", "method", "class"]);

const NUMBER_RE =
  /0x[\da-f][\da-f_]*|0b[01][01_]*|(?:\d[\d_]*)?\.\d[\d_]*(?:e[+-]?\d+)?|\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?/iy;

const WORD_RE = /[A-Za-z_]\w*(?:::\w+)*/y;

const SPECIAL_SCALAR_CHARS = "&`'+/\\,;.<>@!$?:=~^|%\"-";

export const tokenizePerl = (code: string): Token[] => {
  const tokens: Token[] = [];
  let pos = 0;
  let expectName = false;

  const push = (type: TokenType, end: number): void => {
    const text = code.slice(pos, end);
    const last = tokens[tokens.length - 1];
    if (last !== undefined && last.type === type) {
      last.text += text;
    } else {
      tokens.push({ type, text });
    }
    pos = end;
  };

  const matchAt = (re: RegExp): string | null => {
    re.lastIndex = pos;
    const m = re.exec(code);
    return m === null ? null : m[0];
  };

  const quotedEnd = (quote: string): number => {
    for (let i = pos + 1; i < code.length; i++) {
      if (code[i] === "\\") i++;
      else if (code[i] === quote) return i + 1;
    }
    // 閉じ引用符のない編集途中の入力も末尾まで文字列として表示し切る
    return code.length;
  };

  const variableEnd = (): number | null => {
    const sigil = code[pos];
    let i = pos + 1;
    if (sigil === "$") {
      const c = code[i] ?? "";
      if (/\d/.test(c)) {
        let j = i + 1;
        while (j < code.length && /\d/.test(code[j] ?? "")) j++;
        return j;
      }
      if (c === "^" && /[A-Z]/.test(code[i + 1] ?? "")) return i + 2;
      if (c === "#") {
        if (/[A-Za-z_{$]/.test(code[i + 1] ?? "")) i++;
        else return i + 1;
      }
    }
    let j = i;
    while (code[j] === "$") j++;
    if (code[j] === "{") {
      let k = j + 1;
      if (code[k] === "^") k++;
      const start = k;
      while (k < code.length && /\w/.test(code[k] ?? "")) k++;
      if (k > start && code[k] === "}") return k + 1;
    }
    if (/[A-Za-z_]/.test(code[j] ?? "")) {
      let k = j;
      while (k < code.length && /\w/.test(code[k] ?? "")) k++;
      while (code[k] === ":" && code[k + 1] === ":" && /[A-Za-z_]/.test(code[k + 2] ?? "")) {
        k += 2;
        while (k < code.length && /\w/.test(code[k] ?? "")) k++;
      }
      return k;
    }
    if (sigil === "$") {
      if (j > i) return i + 1;
      const c = code[i] ?? "";
      if (c !== "" && SPECIAL_SCALAR_CHARS.includes(c)) return i + 1;
    }
    return null;
  };

  while (pos < code.length) {
    const ch = code[pos] ?? "";
    if (ch === "#") {
      const nl = code.indexOf("\n", pos);
      push(TokenType.COMMENT, nl === -1 ? code.length : nl);
      expectName = false;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === "`") {
      push(TokenType.STRING, quotedEnd(ch));
      expectName = false;
      continue;
    }
    if (ch === "$" || ch === "@" || ch === "%" || ch === "&") {
      const end = variableEnd();
      if (end !== null) {
        push(TokenType.VARIABLE, end);
        expectName = false;
        continue;
      }
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
      } else if (KEYWORDS.has(word)) {
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
