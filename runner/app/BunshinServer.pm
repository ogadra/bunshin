package BunshinServer;
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();
use Socket qw(SOMAXCONN);

our %REASON_PHRASES = (
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    204 => 'No Content',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    307 => 'Temporary Redirect',
    308 => 'Permanent Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    409 => 'Conflict',
    500 => 'Internal Server Error',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
);

sub run {
    my (%opts) = @_;
    my $handler_path = $opts{handler_path} // die "handler_path required\n";
    my $listen_addr  = $opts{listen_addr}  // '0.0.0.0';
    my $listen_port  = $opts{listen_port}  // 5000;

    $SIG{CHLD} = 'IGNORE';
    $| = 1;

    my $server = IO::Socket::INET->new(
        LocalAddr => $listen_addr,
        LocalPort => $listen_port,
        Proto     => 'tcp',
        Listen    => SOMAXCONN,
        ReuseAddr => 1,
    ) or die "listen $listen_addr:$listen_port: $!\n";

    warn "server.pl listening on $listen_addr:$listen_port\n";

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
        handle_conn($conn, handler_path => $handler_path);
        $conn->close;
        POSIX::_exit(0);
    }
}

sub handle_conn {
    my ($conn, %opts) = @_;
    my $handler_path = $opts{handler_path} // die "handler_path required\n";

    my $req = eval { read_request($conn) };
    if (my $err = $@) {
        respond($conn, 400, 'text/plain; charset=utf-8', "bad request: $err");
        return;
    }

    my $handler = load_handler($handler_path);
    if (my $err = $handler->{error}) {
        respond($conn, 500, 'text/plain; charset=utf-8', "handler load failed: $err");
        return;
    }

    my ($status, $ctype, $body);
    my $ok = eval {
        ($status, $ctype, $body) = $handler->{code}->($req->{method}, $req->{path}, $req->{body});
        1;
    };
    if (!$ok) {
        respond($conn, 500, 'text/plain; charset=utf-8', "handler died: $@");
        return;
    }
    respond($conn, $status, $ctype, $body);
}

sub load_handler {
    my ($path) = @_;
    local $@;
    local $!;
    my $code = do $path;
    if (defined $@ and length $@) {
        return { error => "parse: $@" };
    }
    if (!defined $code) {
        return { error => "read $path: " . ($! || 'unknown error') };
    }
    if (ref($code) ne 'CODE') {
        return { error => "$path did not return a CODE ref" };
    }
    return { code => $code };
}

sub read_request {
    my ($conn) = @_;

    my $buf = '';
    while ($buf !~ /\r?\n\r?\n/) {
        my $chunk;
        my $n = sysread $conn, $chunk, 4096;
        die "read: $!\n" if !defined $n;
        die "unexpected EOF before end of headers\n" if $n == 0;
        $buf .= $chunk;
    }

    my ($header, $body_start) = split /\r?\n\r?\n/, $buf, 2;
    $body_start //= '';

    my @lines = split /\r?\n/, $header;
    my $request_line = shift @lines;
    die "empty request line\n" unless defined $request_line and length $request_line;
    my @parts = split / /, $request_line;
    die "malformed request line: $request_line\n" unless @parts >= 2;
    my ($method, $path) = @parts;

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
        die "read body: $!\n" if !defined $n;
        die "body truncated: expected $content_length bytes, got " . length($body) . "\n" if $n == 0;
        $body .= $chunk;
    }

    return { method => $method, path => $path, body => $body };
}

sub respond {
    my ($conn, $status, $ctype, $body) = @_;
    die "respond: status required\n"       unless defined $status;
    die "respond: content type required\n" unless defined $ctype;
    die "respond: body required\n"         unless defined $body;
    my $reason = $REASON_PHRASES{$status}
        // die "respond: unknown status $status (add it to \%REASON_PHRASES)\n";
    utf8::encode($body) if utf8::is_utf8($body);
    my $len = length $body;
    print $conn "HTTP/1.1 $status $reason\r\n";
    print $conn "Content-Type: $ctype\r\n";
    print $conn "Content-Length: $len\r\n";
    print $conn "Connection: close\r\n";
    print $conn "\r\n";
    print $conn $body;
}

1;
