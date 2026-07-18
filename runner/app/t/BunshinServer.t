use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/..";
use BunshinServer;
use Socket qw(AF_UNIX SOCK_STREAM PF_UNSPEC);

# ---------- respond ----------

subtest 'respond writes a well-formed HTTP/1.1 response' => sub {
    my $out = '';
    open my $fh, '>', \$out or die "open scalar: $!";
    BunshinServer::respond($fh, 200, 'text/plain; charset=utf-8', 'hi');
    close $fh;
    like $out, qr{^HTTP/1\.1 200 OK\r\n}, 'status line with known reason phrase';
    like $out, qr{Content-Type: text/plain; charset=utf-8\r\n}, 'Content-Type header';
    like $out, qr{Content-Length: 2\r\n}, 'Content-Length in bytes';
    like $out, qr{Connection: close\r\n}, 'Connection: close';
    like $out, qr{\r\n\r\nhi\z}, 'body follows the header terminator';
};

subtest 'respond measures Content-Length in bytes, not characters' => sub {
    my $out = '';
    open my $fh, '>', \$out or die;
    my $body = "\x{3042}";
    BunshinServer::respond($fh, 200, 'text/plain', $body);
    close $fh;
    like $out, qr{Content-Length: 3\r\n}, 'byte count of a utf8-flagged string';
};

subtest 'respond dies on an unknown status code' => sub {
    my $out = '';
    open my $fh, '>', \$out or die;
    my $ok = eval { BunshinServer::respond($fh, 999, 'text/plain', ''); 1 };
    close $fh;
    ok !$ok, 'respond died';
    like $@, qr{unknown status 999}, 'error names the offending status';
};

subtest 'respond dies on undef status / ctype / body' => sub {
    my $out = '';
    open my $fh, '>', \$out or die;
    my $ok;
    $ok = eval { BunshinServer::respond($fh, undef, 'text/plain', ''); 1 };
    ok !$ok, 'died on undef status';
    like $@, qr{status required};
    $ok = eval { BunshinServer::respond($fh, 200, undef, ''); 1 };
    ok !$ok, 'died on undef content type';
    like $@, qr{content type required};
    $ok = eval { BunshinServer::respond($fh, 200, 'text/plain', undef); 1 };
    ok !$ok, 'died on undef body';
    like $@, qr{body required};
    close $fh;
};

# ---------- read_request ----------

sub make_reader {
    my ($data) = @_;
    my ($server, $client);
    socketpair($server, $client, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
        or die "socketpair: $!";
    syswrite($client, $data) if length $data;
    shutdown($client, 1) or die "shutdown: $!";
    return ($server, $client);
}

subtest 'read_request parses a bare GET' => sub {
    my ($s, $c) = make_reader("GET /a/b HTTP/1.1\r\nHost: x\r\n\r\n");
    my $r = BunshinServer::read_request($s);
    close $s;
    close $c;
    is $r->{method}, 'GET',  'method';
    is $r->{path},   '/a/b', 'path';
    is $r->{body},   '',     'empty body';
};

subtest 'read_request parses a PUT with Content-Length' => sub {
    my ($s, $c) = make_reader("PUT / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello");
    my $r = BunshinServer::read_request($s);
    close $s;
    close $c;
    is $r->{method}, 'PUT';
    is $r->{body},   'hello';
};

subtest 'read_request accepts LF-only line endings' => sub {
    my ($s, $c) = make_reader("GET /lf HTTP/1.1\n\n");
    my $r = BunshinServer::read_request($s);
    close $s;
    close $c;
    is $r->{method}, 'GET';
    is $r->{path},   '/lf';
};

subtest 'read_request treats missing Content-Length as 0' => sub {
    my ($s, $c) = make_reader("POST /x HTTP/1.1\r\nHost: y\r\n\r\n");
    my $r = BunshinServer::read_request($s);
    close $s;
    close $c;
    is $r->{body}, '', 'no Content-Length means zero-length body';
};

subtest 'read_request dies on a malformed request line' => sub {
    my ($s, $c) = make_reader("BADLINE\r\n\r\n");
    my $ok = eval { BunshinServer::read_request($s); 1 };
    close $s;
    close $c;
    ok !$ok, 'died';
    like $@, qr{malformed request line};
};

subtest 'read_request dies on an empty request line' => sub {
    my ($s, $c) = make_reader("\r\n\r\n");
    my $ok = eval { BunshinServer::read_request($s); 1 };
    close $s;
    close $c;
    ok !$ok, 'died';
    like $@, qr{empty request line};
};

subtest 'read_request dies on EOF before the header terminator' => sub {
    my ($s, $c) = make_reader("GET /");
    my $ok = eval { BunshinServer::read_request($s); 1 };
    close $s;
    close $c;
    ok !$ok, 'died';
    like $@, qr{unexpected EOF};
};

subtest 'read_request dies when the body is shorter than Content-Length' => sub {
    my ($s, $c) = make_reader("PUT / HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort");
    my $ok = eval { BunshinServer::read_request($s); 1 };
    close $s;
    close $c;
    ok !$ok, 'died';
    like $@, qr{body truncated};
};

# ---------- handle_conn ----------

sub roundtrip {
    my ($request_data) = @_;
    my ($server, $client);
    socketpair($server, $client, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
        or die "socketpair: $!";
    syswrite($client, $request_data);
    shutdown($client, 1) or die "shutdown: $!";
    BunshinServer::handle_conn($server);
    close $server;
    my $response = do { local $/; <$client> };
    close $client;
    return $response;
}

subtest 'happy path: handler string is embedded in the HTML shell' => sub {
    local $BunshinServer::REFRESH_FN = sub { };
    local $BunshinServer::HANDLER_FN = sub { "Hello from test" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 200 OK\r\n};
    like $r, qr{Content-Type: text/html; charset=utf-8\r\n};
    like $r, qr{<!doctype html>};
    like $r, qr{Hello from test};
};

subtest 'refresh failure yields 500 handler-load-failed' => sub {
    local $BunshinServer::REFRESH_FN = sub { die "parse: line 3 syntax error\n" };
    local $BunshinServer::HANDLER_FN = sub { "never called" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{Content-Type: text/html; charset=utf-8\r\n};
    like $r, qr{handler load failed: parse: line 3 syntax error};
    unlike $r, qr{never called};
};

subtest 'handler dying yields 500 handler-died' => sub {
    local $BunshinServer::REFRESH_FN = sub { };
    local $BunshinServer::HANDLER_FN = sub { die "boom\n" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{handler died: boom};
};

subtest 'handler returning undef yields 500' => sub {
    local $BunshinServer::REFRESH_FN = sub { };
    local $BunshinServer::HANDLER_FN = sub { undef };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{^HTTP/1\.1 500 Internal Server Error\r\n};
    like $r, qr{returned undef};
};

subtest 'malformed request yields 400 bad request' => sub {
    local $BunshinServer::REFRESH_FN = sub { };
    local $BunshinServer::HANDLER_FN = sub { "unused" };
    my $r = roundtrip("BADLINE\r\n\r\n");
    like $r, qr{^HTTP/1\.1 400 Bad Request\r\n};
    like $r, qr{Content-Type: text/plain; charset=utf-8\r\n};
    like $r, qr{bad request:};
};

subtest 'error page escapes HTML metacharacters' => sub {
    local $BunshinServer::REFRESH_FN = sub { die "<script>alert(&x)</script>\n" };
    local $BunshinServer::HANDLER_FN = sub { "unused" };
    my $r = roundtrip("GET / HTTP/1.1\r\n\r\n");
    like $r, qr{&lt;script&gt;alert\(&amp;x\)&lt;/script&gt;}, 'metacharacters escaped';
    unlike $r, qr{<script>alert}, 'raw tag not present';
};

done_testing;
