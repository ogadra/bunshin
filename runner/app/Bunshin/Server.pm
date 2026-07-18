package Bunshin::Server;
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();
use Socket qw(SOMAXCONN);

sub run {
    my (%opts) = @_;
    my $listen_addr = $opts{listen_addr} // die "listen_addr required\n";
    my $listen_port = $opts{listen_port} // die "listen_port required\n";
    my $handler     = $opts{handler}     // die "handler required\n";

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
        my $ok = eval { $handler->($conn); 1 };
        warn "handler died: $@" unless $ok;
        $conn->close;
        POSIX::_exit($ok ? 0 : 1);
    }
}

1;
