use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use File::Temp qw(tempfile);
use Encode ();
use lib "$FindBin::Bin/../..";

BEGIN {
    my ($fh1, $counter) = tempfile(UNLINK => 1); close $fh1; unlink $counter;
    my ($fh2, $record)  = tempfile(UNLINK => 1); close $fh2; unlink $record;
    $ENV{BUNSHIN_QUIZ_COUNTER} = $counter;
    $ENV{BUNSHIN_QUIZ_RECORD}  = $record;
}

use Bunshin::App;
use DaiKichijoji;
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);

binmode Test::More->builder->$_, ':encoding(UTF-8)'
    for qw(output failure_output todo_output);

sub roundtrip {
    my ($request_data) = @_;
    my ($server, $client);
    socketpair($server, $client, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
        or die "socketpair: $!";
    syswrite($client, $request_data);
    shutdown($client, 1) or die "shutdown: $!";
    Bunshin::App::handle_conn($server);
    close $server;
    my $response = do { local $/; <$client> };
    close $client;
    return $response;
}

subtest 'happy path: ok body is embedded in the HTML shell' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'ok', body => "Hello from test" } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 200 OK\r\n};
    like $r, qr{Content-Type: text/html; charset=utf-8\r\n};
    like $r, qr{<!doctype html>};
    like $r, qr{Hello from test};
};

subtest 'content is embedded as raw HTML' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'ok', body => "<b>bold</b>" } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{<b>bold</b>}, 'raw tag passes through';
    unlike $r, qr{&lt;b&gt;bold&lt;/b&gt;}, 'no over-escaping';
};

subtest 'refresh failure surfaces the load-failed message from the runner' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { die "DaiKichijoji.pm load failed: parse: line 3 syntax error\n" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{Content-Type: text/html; charset=utf-8\r\n};
    like $r, qr{DaiKichijoji.pm load failed: parse: line 3 syntax error};
};

subtest 'died status yields 500 with the error message' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'died', error => "boom at DaiKichijoji.pm line 5" } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content died: boom at DaiKichijoji.pm line 5};
};

subtest 'exited status yields 500 with exit code' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'exited', code => 42 } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content exited with code 42};
};

subtest 'exited status with code 0 also yields 500' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'exited', code => 0 } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content exited with code 0};
};

subtest 'timed_out status yields 500 with elapsed budget' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'timed_out', ms => 3000 } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content timed out: exceeded 3000ms};
};

subtest 'runner throwing an exception yields 500 with the raw error' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { die "runner internal error\n" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{runner internal error};
};

subtest 'runner returning undef yields 500 tagged undef' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { undef };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{content runner returned undef};
};

subtest 'runner returning a non-hash scalar yields 500 tagged as invalid' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { 0 };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{content runner returned invalid result: non-ref scalar};
};

subtest 'runner returning a non-hash reference yields 500 tagged with the ref type' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { [] };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{content runner returned invalid result: ARRAY};
};

subtest 'malformed request yields 400 bad request' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'ok', body => "unused" } };
    my $r = roundtrip("GET /");
    like $r, qr{^HTTP/1\.1 400 Bad Request\r\n};
    like $r, qr{Content-Type: text/plain; charset=utf-8\r\n};
    like $r, qr{bad request:};
};

subtest 'error page escapes HTML metacharacters' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { die "<script>alert(&x)</script>\n" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{&lt;script&gt;alert\(&amp;x\)&lt;/script&gt;}, 'metacharacters escaped';
    unlike $r, qr{<script>alert}, 'raw tag not present';
};

subtest 'real defaults: refresh failure gets wrapped with the load-failed prefix' => sub {
    no warnings 'redefine';
    my $orig = \&Module::Refresh::refresh;
    local *Module::Refresh::refresh = sub { die "parse: line 3 syntax error\n" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    local *Module::Refresh::refresh = $orig;
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji\.pm load failed: parse: line 3 syntax error};
};

subtest 'real defaults: Compilation-failed-in-require warning surfaces on the 500 page' => sub {
    no warnings 'redefine';
    local *Module::Refresh::refresh = sub {
        warn "syntax error at /app/DaiKichijoji.pm line 2, at EOF\nCompilation failed in require at Module/Refresh.pm line 121.\n";
    };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji\.pm load failed:};
    like $r, qr{syntax error at /app/DaiKichijoji\.pm line 2};
};

subtest 'real defaults: aborted-due-to-compilation-errors warning also surfaces on the 500 page' => sub {
    no warnings 'redefine';
    local *Module::Refresh::refresh = sub {
        warn "Execution of /app/DaiKichijoji.pm aborted due to compilation errors.\n";
    };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji\.pm load failed:};
    like $r, qr{aborted due to compilation errors};
};

subtest 'real defaults: non-compile warnings from refresh pass through to STDERR' => sub {
    no warnings 'redefine';
    local *Module::Refresh::refresh = sub {
        warn "Use of uninitialized value in something at foo.pm line 5.\n";
    };
    my $stderr = '';
    open(my $saved_stderr, '>&', \*STDERR) or die "dup STDERR: $!";
    close STDERR;
    open(STDERR, '>', \$stderr)            or die "capture STDERR: $!";
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    open(STDERR, '>&', $saved_stderr)      or die "restore STDERR: $!";
    like $r,       qr{^HTTP/1\.1 200 OK\r\n},                'no 500';
    like $stderr,  qr{Use of uninitialized value},           're-emitted to STDERR';
};

subtest 'integration: real Module::Refresh + a real broken file dies with the compiler diagnostic' => sub {
    require File::Temp;
    my $tmpdir   = File::Temp->newdir;
    my $mod_name = "BunshinTestFake_$$";
    my $mod_file = "$mod_name.pm";
    my $mod_path = "$tmpdir/$mod_file";

    local @INC = (@INC, "$tmpdir");

    open my $fh, '>', $mod_path or die "write initial: $!";
    print $fh "package $mod_name;\nsub content { 'ok' }\n1;\n";
    close $fh;
    utime time - 2, time - 2, $mod_path;

    require $mod_file;
    Module::Refresh->refresh;

    open my $fh2, '>', $mod_path or die "rewrite broken: $!";
    print $fh2 "package $mod_name;\nsub content { 'broken'\n";
    close $fh2;
    utime time, time, $mod_path;

    my $ok = eval { $Bunshin::App::RUN_CONTENT_FN->(); 1 };
    my $err = $@;

    delete $INC{$mod_file};
    { no strict 'refs'; delete $::{"${mod_name}::"}; }

    ok !$ok, 'RUN_CONTENT_FN dies when Module::Refresh warns on a real compile error';
    like $err, qr{DaiKichijoji\.pm load failed:}, 'wrapped with load-failed prefix';
    like $err, qr{Compilation failed in require}, 'carries the require diagnostic';
    like $err, qr{\Q$mod_name\E\.pm},              'names the broken file';
};

subtest 'real defaults: dispatches through the real ContentRunner and DaiKichijoji' => sub {
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 200 OK\r\n};
    my $heading = Encode::encode('UTF-8', '大吉祥寺.pm');
    my $counter = Encode::encode('UTF-8', 'アクセス数');
    like $r, qr{\Q$heading\E}, 'the quiz page heading is served';
    like $r, qr{\Q$counter\E}, 'the counter section is rendered';
};

subtest 'real defaults: 500 when DaiKichijoji::content is missing' => sub {
    my $orig = \&DaiKichijoji::content;
    { no strict 'refs'; delete ${'DaiKichijoji::'}{content}; }
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    { no strict 'refs'; *{'DaiKichijoji::content'} = $orig; }
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content died: DaiKichijoji::content is not defined};
};

done_testing;
