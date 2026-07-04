import { describe, test, expect } from "vitest";
import { bracedVariableEnd, specialScalarEnd, tokenizePerl, TokenType, wordPathEnd } from "./perl";

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
    ["an unclosed quote-like operator", "s{unclosed"],
    ["a heredoc without terminator", 'my $t = <<"EOF";\nbody'],
    ["a heredoc declared at end of input", "my $t = <<EOF;"],
    ["POD without =cut", "=pod\nstill pod"],
    ["unclosed nested delimiters", "q{a{b}"],
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

describe("specialScalarEnd", () => {
  test("consumes digit variables like $22", () => {
    expect(specialScalarEnd("$22;", 0)).toBe(3);
  });

  test("consumes caret variables like $^W", () => {
    expect(specialScalarEnd("$^W", 0)).toBe(3);
  });

  test("consumes a bare $#", () => {
    expect(specialScalarEnd("$# ", 0)).toBe(2);
  });

  test("leaves $#array to the identifier path", () => {
    expect(specialScalarEnd("$#array", 0)).toBeNull();
  });

  test("leaves named variables to the identifier path", () => {
    expect(specialScalarEnd("$name", 0)).toBeNull();
  });
});

describe("wordPathEnd", () => {
  test("consumes a word", () => {
    expect(wordPathEnd("foo+bar", 0)).toBe(3);
  });

  test("consumes :: chains", () => {
    expect(wordPathEnd("Foo::Bar::baz;", 0)).toBe(13);
  });

  test("stops before a trailing ::", () => {
    expect(wordPathEnd("foo::", 0)).toBe(3);
  });

  test("starts from the given offset", () => {
    expect(wordPathEnd("${name}", 2)).toBe(6);
  });

  test("allows digit-leading names for braced forms", () => {
    expect(wordPathEnd("2x", 0)).toBe(2);
  });
});

describe("bracedVariableEnd", () => {
  test("consumes ${name}", () => {
    expect(bracedVariableEnd("${name}", 1, "$")).toBe(7);
  });

  test("consumes ${Foo::Bar}", () => {
    expect(bracedVariableEnd("${Foo::Bar}", 1, "$")).toBe(11);
  });

  test("consumes caret names like ${^GLOBAL_PHASE}", () => {
    expect(bracedVariableEnd("${^GLOBAL_PHASE}", 1, "$")).toBe(16);
  });

  test("accepts punctuation specials only for the $ sigil", () => {
    expect(bracedVariableEnd("${!}", 1, "$")).toBe(4);
    expect(bracedVariableEnd("@{!}", 1, "@")).toBeNull();
  });

  test("rejects an unclosed brace", () => {
    expect(bracedVariableEnd("${unclosed", 1, "$")).toBeNull();
  });

  test("rejects empty braces", () => {
    expect(bracedVariableEnd("${}", 1, "$")).toBeNull();
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

describe("quote-like operators", () => {
  test.each([
    ["q(a b)"],
    ["qq{hi there}"],
    ["qw(a b c)"],
    ["qx(ls -l)"],
    ["q!bang!"],
    ["q^caret^"],
    ["q#hash#"],
    ["q|pipe|"],
    ["q=equals="],
    ["q.dot."],
  ])("%s is a string", (quoted) => {
    expect(textsOf(`my $x = ${quoted};`, TokenType.STRING)).toEqual([quoted]);
  });

  test("whitespace may separate the operator from its delimiter", () => {
    expect(textsOf("my $x = q (a b);", TokenType.STRING)).toEqual(["q (a b)"]);
  });

  test("a hash delimiter must follow the operator immediately", () => {
    expect(textsOf("q #comment", TokenType.STRING)).toEqual([]);
    expect(textsOf("q #comment", TokenType.COMMENT)).toEqual(["#comment"]);
  });

  test("paired delimiters nest", () => {
    expect(textsOf("my $x = q{a{b}c};", TokenType.STRING)).toEqual(["q{a{b}c}"]);
  });

  test("escaped delimiter stays inside", () => {
    expect(textsOf("q(a\\)b)", TokenType.STRING)).toEqual(["q(a\\)b)"]);
  });

  test("q before a fat comma is a plain hash key context", () => {
    expect(textsOf("my %h = (q => 1);", TokenType.STRING)).toEqual([]);
  });

  test("unclosed operator runs to the end of input", () => {
    expect(textsOf("my $x = q{oops", TokenType.STRING)).toEqual(["q{oops"]);
  });
});

describe("regexp operators", () => {
  test.each([
    ["m/\\d+/"],
    ["m{pat}i"],
    ["m|pat|i"],
    ["qr/^a.*z$/ms"],
    ["s/foo/bar/g"],
    ["s{foo}{bar}g"],
    ["s {foo} {bar}g"],
    ["tr/a-z/A-Z/"],
    ["tr [a-z] [A-Z]"],
    ["y/abc/xyz/"],
  ])("%s is a regexp", (re) => {
    expect(textsOf(`$x =~ ${re};`, TokenType.REGEXP)).toEqual([re]);
  });

  test("a substitution as a fat comma value is recognized", () => {
    expect(textsOf("my %h = (a => s/foo/bar/g);", TokenType.REGEXP)).toEqual(["s/foo/bar/g"]);
  });

  test("a substitution after a comparison is recognized", () => {
    expect(textsOf("$count > s{foo}{bar}g;", TokenType.REGEXP)).toEqual(["s{foo}{bar}g"]);
  });

  test("a missing second part does not swallow the following word", () => {
    expect(textsOf("s{foo}bar;", TokenType.REGEXP)).toEqual(["s{foo}"]);
  });

  test("a word run containing non-modifier letters is not consumed as modifiers", () => {
    expect(textsOf("$x =~ /foo/if 1;", TokenType.REGEXP)).toEqual(["/foo/"]);
    expect(textsOf("$x =~ /foo/if 1;", TokenType.KEYWORD)).toContain("if");
  });

  test("bare slashes after a binding operator are a regexp", () => {
    expect(textsOf("$x =~ /foo/i;", TokenType.REGEXP)).toEqual(["/foo/i"]);
  });

  test("a pattern after split is a regexp", () => {
    expect(textsOf("split /,/, $line;", TokenType.REGEXP)).toEqual(["/,/"]);
  });

  test("paired two-part substitution allows whitespace between parts", () => {
    expect(textsOf("s{foo}\n  {bar}g;", TokenType.REGEXP)).toEqual(["s{foo}\n  {bar}g"]);
  });

  test("slash after a variable is division", () => {
    expect(textsOf("$a / $b", TokenType.REGEXP)).toEqual([]);
  });

  test("slash after a number is division", () => {
    expect(textsOf("10 / 2", TokenType.REGEXP)).toEqual([]);
  });

  test("slash after a closing paren is division", () => {
    expect(textsOf("f() / 2", TokenType.REGEXP)).toEqual([]);
  });

  test("defined-or after a variable is not a regexp", () => {
    expect(textsOf("$x // 5", TokenType.REGEXP)).toEqual([]);
  });

  test("s as a hash key is not a substitution", () => {
    expect(textsOf("$h{s}", TokenType.REGEXP)).toEqual([]);
  });

  test("s as a method name is not a substitution", () => {
    expect(textsOf("$obj->s(2)", TokenType.REGEXP)).toEqual([]);
  });
});

describe("heredocs", () => {
  test("body up to the terminator line is a string", () => {
    const code = "my $t = <<EOF;\nline1\nline2\nEOF\nprint;";
    expect(textsOf(code, TokenType.STRING)).toEqual(["<<EOF", "line1\nline2\nEOF\n"]);
    expect(textsOf(code, TokenType.KEYWORD)).toContain("print");
  });

  test("indented terminator closes <<~", () => {
    const code = "my $t = <<~EOF;\n  text\n  EOF\n";
    expect(textsOf(code, TokenType.STRING)).toEqual(["<<~EOF", "  text\n  EOF\n"]);
  });

  test.each([['<<"EOF"'], ["<<'EOF'"], ["<<`EOF`"]])("%s declares a heredoc", (marker) => {
    const code = `my $t = ${marker};\nbody\nEOF\n`;
    expect(textsOf(code, TokenType.STRING)).toEqual([marker, "body\nEOF\n"]);
  });

  test('indented terminator closes the quoted form <<~"EOF"', () => {
    const code = 'my $t = <<~"EOF";\n  body\n  EOF\n';
    expect(textsOf(code, TokenType.STRING)).toEqual(['<<~"EOF"', "  body\n  EOF\n"]);
  });

  test("CRLF line endings still close the heredoc", () => {
    const code = "my $t = <<EOF;\r\nbody\r\nEOF\r\nprint;";
    expect(textsOf(code, TokenType.STRING)).toEqual(["<<EOF", "body\r\nEOF\r\n"]);
    expect(textsOf(code, TokenType.KEYWORD)).toContain("print");
  });

  test("a pattern on the line after the terminator is a regexp", () => {
    const code = "my $t = <<EOF;\nbody\nEOF\n/pat/;";
    expect(textsOf(code, TokenType.REGEXP)).toEqual(["/pat/"]);
  });

  test("two heredocs on one line are consumed in order", () => {
    const code = "print <<A, <<B;\naaa\nA\nbbb\nB\nsay;";
    expect(textsOf(code, TokenType.STRING)).toEqual(["<<A", "<<B", "aaa\nA\nbbb\nB\n"]);
    expect(textsOf(code, TokenType.KEYWORD)).toContain("say");
  });

  test("heredoc without terminator runs to the end of input", () => {
    expect(textsOf("my $t = <<EOF;\nbody", TokenType.STRING)).toEqual(["<<EOF", "body"]);
  });

  test("left shift is not a heredoc", () => {
    expect(textsOf("$a << 2;\nrest\n", TokenType.STRING)).toEqual([]);
  });
});

describe("POD and data sections", () => {
  test("=pod through =cut is a comment", () => {
    const code = "=pod\ndocs here\n=cut trailing\nmy $x;";
    expect(textsOf(code, TokenType.COMMENT)).toEqual(["=pod\ndocs here\n=cut trailing"]);
    expect(textsOf(code, TokenType.KEYWORD)).toEqual(["my"]);
  });

  test("any =word directive opens POD", () => {
    expect(textsOf("=head1 TITLE\nprose\n=cut\n", TokenType.COMMENT)).toEqual([
      "=head1 TITLE\nprose\n=cut",
    ]);
  });

  test("POD without =cut runs to the end of input", () => {
    expect(textsOf("=pod\nstill pod", TokenType.COMMENT)).toEqual(["=pod\nstill pod"]);
  });

  test("mid-line = is not POD", () => {
    expect(textsOf("my $x = 1;", TokenType.COMMENT)).toEqual([]);
  });

  test.each([["__END__"], ["__DATA__"]])("%s comments out the rest of the file", (marker) => {
    const code = `my $x;\n${marker}\nanything "goes" here`;
    expect(textsOf(code, TokenType.COMMENT)).toEqual([`${marker}\nanything "goes" here`]);
  });

  test("__END__ not at line start is a plain word", () => {
    expect(textsOf("foo __END__ bar", TokenType.COMMENT)).toEqual([]);
  });
});
