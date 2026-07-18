package BunshinServer;
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();
use Socket qw(SOMAXCONN);
use Module::Refresh;

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

my $HTML_SHELL = <<'HTML';
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>bunshin perl demo — 大吉祥寺.pm</title>
<style>
body { font-family: system-ui, sans-serif; margin: 2rem; line-height: 1.6; }
pre { background: #fee; padding: 1rem; border-radius: 4px; overflow: auto; }
</style>
</head>
<body>
%s
</body>
</html>
HTML

our $REFRESH_FN = sub { Module::Refresh->refresh };
our $CONTENT_FN = sub {
    my $sub = DaiKichijoji->can('content')
        or die "DaiKichijoji::content is not defined\n";
    $sub->();
};

sub run {
    my (%opts) = @_;
    my $listen_addr = $opts{listen_addr} // '0.0.0.0';
    my $listen_port = $opts{listen_port} // 5000;

    $SIG{CHLD} = 'IGNORE';
    $| = 1;

    my $server = IO::Socket::INET->new(
        LocalAddr => $listen_addr,
        LocalPort => $listen_port,
        Proto     => 'tcp',
        Listen    => SOMAXCONN,
        ReuseAddr => 1,
    ) or die "listen $listen_addr:$listen_port: $!\n";

    Module::Refresh->refresh;

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
        handle_conn($conn);
        $conn->close;
        POSIX::_exit(0);
    }
}

sub handle_conn {
    my ($conn) = @_;

    my $req = eval { read_request($conn) };
    if (my $err = $@) {
        respond($conn, 400, 'text/plain; charset=utf-8', "bad request: $err");
        return;
    }

    my $refresh_ok = eval { $REFRESH_FN->(); 1 };
    if (!$refresh_ok) {
        respond($conn, 500, 'text/html; charset=utf-8', build_error_page("DaiKichijoji.pm load failed: $@"));
        return;
    }

    my $body;
    my $call_ok = eval { $body = $CONTENT_FN->(); 1 };
    if (!$call_ok) {
        respond($conn, 500, 'text/html; charset=utf-8', build_error_page("DaiKichijoji::content died: $@"));
        return;
    }
    if (!defined $body) {
        respond($conn, 500, 'text/html; charset=utf-8', build_error_page("DaiKichijoji::content returned undef"));
        return;
    }

    respond($conn, 200, 'text/html; charset=utf-8', sprintf($HTML_SHELL, $body));
}

sub build_error_page {
    my ($msg) = @_;
    my $escaped = $msg;
    $escaped =~ s/&/&amp;/g;
    $escaped =~ s/</&lt;/g;
    $escaped =~ s/>/&gt;/g;
    return sprintf($HTML_SHELL, "<h1>Error</h1>\n<pre>$escaped</pre>");
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
