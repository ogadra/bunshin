use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use Bunshin::App;
use DaiKichijoji;
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);

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

subtest 'content HTML metacharacters are escaped' => sub {
    local $Bunshin::App::RUN_CONTENT_FN = sub { +{ status => 'ok', body => "<b>bold</b>" } };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{&lt;b&gt;bold&lt;/b&gt;}, 'metacharacters escaped';
    unlike $r, qr{<b>bold</b>}, 'raw tag not present';
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

subtest 'real defaults: dispatches through the real ContentRunner and DaiKichijoji' => sub {
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 200 OK\r\n};
    like $r, qr{Hello from DaiKichijoji};
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
