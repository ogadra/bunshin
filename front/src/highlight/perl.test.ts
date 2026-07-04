import { describe, test, expect } from "vitest";
import { tokenizePerl, TokenType } from "./perl";

const rejoin = (code: string): string =>
  tokenizePerl(code)
    .map((t) => t.text)
    .join("");

const textsOf = (code: string, type: TokenType): string[] =>
  tokenizePerl(code)
    .filter((t) => t.type === type)
    .map((t) => t.text);

const SAMPLE = `#!/usr/bin/perl
use strict;
use warnings;

package Greeter::Simple;

sub greet {
    my ($self, $name) = @_;
    my $count = 1_000;
    print "hello, $name\\n";
    return $count * 0.5; # half
}
`;

describe("invariants", () => {
  const inputs: [string, string][] = [
    ["a full script", SAMPLE],
    ["an empty input", ""],
    ["an unclosed string", 'print "oops'],
    ["lone sigils", "$ @ % & $"],
    ["an unclosed ${", "${unclosed"],
    ["only newlines", "\n\n\n"],
    ["non-ascii text", "print 'こんにちは'; # 日本語"],
  ];

  test.each(inputs)("concatenated token texts equal the input for %s", (_, code) => {
    expect(rejoin(code)).toBe(code);
  });

  test.each(inputs)("never emits two consecutive tokens of the same type for %s", (_, code) => {
    const tokens = tokenizePerl(code);
    for (let i = 1; i < tokens.length; i++) {
      expect(tokens[i]!.type).not.toBe(tokens[i - 1]!.type);
    }
  });
});

describe("comments", () => {
  test("# to end of line is a comment", () => {
    expect(textsOf("print;  # note\n", TokenType.COMMENT)).toEqual(["# note"]);
  });

  test("hash inside a string is not a comment", () => {
    expect(textsOf('"a # b"', TokenType.COMMENT)).toEqual([]);
  });

  test("code after the newline is tokenized normally", () => {
    expect(textsOf("# note\nmy $x;", TokenType.KEYWORD)).toEqual(["my"]);
  });
});

describe("strings", () => {
  test("single-quoted string", () => {
    expect(textsOf("my $s = 'hello';", TokenType.STRING)).toEqual(["'hello'"]);
  });

  test("double-quoted string", () => {
    expect(textsOf('my $s = "hello";', TokenType.STRING)).toEqual(['"hello"']);
  });

  test("backtick command string", () => {
    expect(textsOf("my $out = `ls -l`;", TokenType.STRING)).toEqual(["`ls -l`"]);
  });

  test("escaped quote stays inside the string", () => {
    expect(textsOf("'a\\'b'", TokenType.STRING)).toEqual(["'a\\'b'"]);
  });

  test("string spans multiple lines", () => {
    expect(textsOf('"line1\nline2"', TokenType.STRING)).toEqual(['"line1\nline2"']);
  });

  test("unclosed string runs to the end of input", () => {
    expect(textsOf('print "oops', TokenType.STRING)).toEqual(['"oops']);
  });
});

describe("variables", () => {
  test("scalar, array and hash sigils", () => {
    expect(textsOf("my ($s, @a, %h);", TokenType.VARIABLE)).toEqual(["$s", "@a", "%h"]);
  });

  test("braced name ${name}", () => {
    expect(textsOf("${name}", TokenType.VARIABLE)).toEqual(["${name}"]);
  });

  test("capture group variables", () => {
    expect(textsOf("print $1 . $22;", TokenType.VARIABLE)).toEqual(["$1", "$22"]);
  });

  test("punctuation variables", () => {
    expect(textsOf("$_ $! $@ $/ $0 $$", TokenType.VARIABLE)).toEqual([
      "$_",
      "$!",
      "$@",
      "$/",
      "$0",
      "$$",
    ]);
  });

  test("caret variable $^W", () => {
    expect(textsOf("$^W", TokenType.VARIABLE)).toEqual(["$^W"]);
  });

  test("last-index variable $#array", () => {
    expect(textsOf("$#array", TokenType.VARIABLE)).toEqual(["$#array"]);
  });

  test("dereference chains", () => {
    expect(textsOf("$$ref @$ref", TokenType.VARIABLE)).toEqual(["$$ref", "@$ref"]);
  });

  test("package-qualified name", () => {
    expect(textsOf("$Foo::Bar::baz", TokenType.VARIABLE)).toEqual(["$Foo::Bar::baz"]);
  });

  test("braced package-qualified name", () => {
    expect(textsOf("${Foo::Bar::baz}", TokenType.VARIABLE)).toEqual(["${Foo::Bar::baz}"]);
  });

  test("braced punctuation variable", () => {
    expect(textsOf("${!}", TokenType.VARIABLE)).toEqual(["${!}"]);
  });

  test("% is an operator when not followed by an identifier", () => {
    expect(textsOf("5 % 2", TokenType.VARIABLE)).toEqual([]);
  });

  test("& is an operator between variables", () => {
    expect(textsOf("$a & $b", TokenType.VARIABLE)).toEqual(["$a", "$b"]);
  });

  test("&name is a function-call sigil", () => {
    expect(textsOf("&run()", TokenType.VARIABLE)).toEqual(["&run"]);
  });
});

describe("numbers", () => {
  test.each([
    ["42"],
    ["3.14"],
    [".5"],
    ["1_000_000"],
    ["0xDEAD_beef"],
    ["0b1010"],
    ["6.02e23"],
    ["1e-10"],
  ])("%s is a number", (num) => {
    expect(textsOf(`my $x = ${num};`, TokenType.NUMBER)).toEqual([num]);
  });

  test("range operator stays out of numbers", () => {
    expect(textsOf("1..10", TokenType.NUMBER)).toEqual(["1", "10"]);
  });
});

describe("keywords", () => {
  test("declarations and control flow", () => {
    expect(textsOf("my $x; return $x if defined $x;", TokenType.KEYWORD)).toEqual([
      "my",
      "return",
      "if",
      "defined",
    ]);
  });

  test("a keyword prefix inside a longer word is not a keyword", () => {
    expect(textsOf("mystery()", TokenType.KEYWORD)).toEqual([]);
  });

  test("unknown bare words are plain", () => {
    expect(textsOf("frobnicate();", TokenType.KEYWORD)).toEqual([]);
  });
});

describe("declared names", () => {
  test("sub name is a function", () => {
    expect(textsOf("sub greet { }", TokenType.FUNCTION)).toEqual(["greet"]);
  });

  test("package name is a function", () => {
    expect(textsOf("package Foo::Bar;", TokenType.FUNCTION)).toEqual(["Foo::Bar"]);
  });

  test("anonymous sub declares no name", () => {
    expect(textsOf("my $f = sub { 1 };", TokenType.FUNCTION)).toEqual([]);
  });

  test("a comment between sub and its name is skipped like whitespace", () => {
    expect(textsOf("sub # note\nfoo { }", TokenType.FUNCTION)).toEqual(["foo"]);
  });
});
