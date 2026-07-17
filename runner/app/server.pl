#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();

$SIG{CHLD} = 'IGNORE';
$| = 1;

my $HANDLER_PATH = '/app/handler.pl';
my $LISTEN_ADDR  = '0.0.0.0';
my $LISTEN_PORT  = 5000;

my $server = IO::Socket::INET->new(
    LocalAddr => $LISTEN_ADDR,
    LocalPort => $LISTEN_PORT,
    Proto     => 'tcp',
    Listen    => SOMAXCONN,
    ReuseAddr => 1,
) or die "listen $LISTEN_ADDR:$LISTEN_PORT: $!\n";

warn "server.pl listening on $LISTEN_ADDR:$LISTEN_PORT\n";

while (my $conn = $server->accept) {
    my $pid = fork;
    if (!defined $pid) {
        warn "fork failed: $!\n";
        $conn->close;
        next;
    }
    if ($pid) {
        $conn->close;
        next;
    }
    $server->close;
    handle_conn($conn);
    $conn->close;
    POSIX::_exit(0);
}

sub handle_conn {
    my ($conn) = @_;
    my $req = read_request($conn);
    return unless $req;

    my ($method, $path, $body) = @$req;

    my $handler = do $HANDLER_PATH;
    if (!$handler || ref($handler) ne 'CODE') {
        my $err = $@ || $! || "$HANDLER_PATH did not return a CODE ref";
        respond($conn, 500, 'text/plain; charset=utf-8', "handler load failed: $err");
        return;
    }

    my ($status, $ctype, $resp);
    my $ok = eval {
        ($status, $ctype, $resp) = $handler->($method, $path, $body);
        1;
    };
    if (!$ok) {
        respond($conn, 500, 'text/plain; charset=utf-8', "handler died: $@");
        return;
    }
    respond($conn, $status, $ctype, $resp);
}

sub read_request {
    my ($conn) = @_;
    my $buf = '';
    while ($buf !~ /\r?\n\r?\n/) {
        my $chunk;
        my $n = sysread $conn, $chunk, 4096;
        last unless $n;
        $buf .= $chunk;
    }
    return undef unless length $buf;

    my ($header, $body_start) = split /\r?\n\r?\n/, $buf, 2;
    $body_start //= '';
    my @lines = split /\r?\n/, $header;
    my $request_line = shift @lines;
    return undef unless defined $request_line;
    my ($method, $path) = split / /, $request_line, 3;
    return undef unless defined $method && defined $path;

    my $content_length = 0;
    for my $line (@lines) {
        if ($line =~ /^Content-Length:\s*(\d+)/i) {
            $content_length = $1 + 0;
            last;
        }
    }

    my $body = $body_start;
    while (length($body) < $content_length) {
        my $chunk;
        my $n = sysread $conn, $chunk, $content_length - length($body);
        last unless $n;
        $body .= $chunk;
    }

    return [$method, $path, $body];
}

sub respond {
    my ($conn, $status, $ctype, $body) = @_;
    $status //= 500;
    $ctype  //= 'text/plain; charset=utf-8';
    $body   //= '';
    my $reason = $status == 200 ? 'OK'
               : $status == 204 ? 'No Content'
               : $status == 400 ? 'Bad Request'
               : $status == 404 ? 'Not Found'
               : $status == 500 ? 'Internal Server Error'
               : 'OK';
    my $len = length $body;
    print $conn "HTTP/1.1 $status $reason\r\n";
    print $conn "Content-Type: $ctype\r\n";
    print $conn "Content-Length: $len\r\n";
    print $conn "Connection: close\r\n";
    print $conn "\r\n";
    print $conn $body;
}
