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

subtest 'happy path: content string is embedded in the HTML shell' => sub {
    local $Bunshin::App::REFRESH_FN = sub { };
    local $Bunshin::App::CONTENT_FN = sub { "Hello from test" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 200 OK\r\n};
    like $r, qr{Content-Type: text/html; charset=utf-8\r\n};
    like $r, qr{<!doctype html>};
    like $r, qr{Hello from test};
};

subtest 'content HTML metacharacters are escaped' => sub {
    local $Bunshin::App::REFRESH_FN = sub { };
    local $Bunshin::App::CONTENT_FN = sub { "<b>bold</b>" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{&lt;b&gt;bold&lt;/b&gt;}, 'metacharacters escaped';
    unlike $r, qr{<b>bold</b>}, 'raw tag not present';
};

subtest 'refresh failure yields 500 with load-failed page' => sub {
    local $Bunshin::App::REFRESH_FN = sub { die "parse: line 3 syntax error\n" };
    local $Bunshin::App::CONTENT_FN = sub { "never called" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{Content-Type: text/html; charset=utf-8\r\n};
    like $r, qr{DaiKichijoji.pm load failed: parse: line 3 syntax error};
    unlike $r, qr{never called};
};

subtest 'DaiKichijoji::content dying yields 500 with a stack trace' => sub {
    local $Bunshin::App::REFRESH_FN = sub { };
    local $Bunshin::App::CONTENT_FN = sub { die "boom\n" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content died: boom}, 'die message present';
    like $r, qr{Bunshin::App::handle_conn}, 'stack trace names handle_conn frame';
};

subtest 'DaiKichijoji::content returning undef yields 500' => sub {
    local $Bunshin::App::REFRESH_FN = sub { };
    local $Bunshin::App::CONTENT_FN = sub { undef };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content returned undef};
};

subtest 'malformed request yields 400 bad request' => sub {
    local $Bunshin::App::REFRESH_FN = sub { };
    local $Bunshin::App::CONTENT_FN = sub { "unused" };
    my $r = roundtrip("GET /");
    like $r, qr{^HTTP/1\.1 400 Bad Request\r\n};
    like $r, qr{Content-Type: text/plain; charset=utf-8\r\n};
    like $r, qr{bad request:};
};

subtest 'error page escapes HTML metacharacters' => sub {
    local $Bunshin::App::REFRESH_FN = sub { die "<script>alert(&x)</script>\n" };
    local $Bunshin::App::CONTENT_FN = sub { "unused" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{&lt;script&gt;alert\(&amp;x\)&lt;/script&gt;}, 'metacharacters escaped';
    unlike $r, qr{<script>alert}, 'raw tag not present';
};

subtest 'real defaults: DaiKichijoji::content dispatches through the real $CONTENT_FN and $REFRESH_FN' => sub {
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 200 OK\r\n};
    like $r, qr{Hello from DaiKichijoji}, 'default $CONTENT_FN returned DaiKichijoji::content output';
};

subtest 'real defaults: 500 when DaiKichijoji::content is missing' => sub {
    my $orig = \&DaiKichijoji::content;
    { no strict 'refs'; delete ${'DaiKichijoji::'}{content}; }
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    { no strict 'refs'; *{'DaiKichijoji::content'} = $orig; }
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{DaiKichijoji::content is not defined};
};

done_testing;
