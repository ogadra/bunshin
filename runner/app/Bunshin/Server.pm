package Bunshin::Server;
use strict;
use warnings;
use IO::Socket::INET;
use POSIX ();
use Socket qw(SOMAXCONN);

sub run {
    my (%opts) = @_;
    my $listen_addr = $opts{listen_addr} // '0.0.0.0';
    my $listen_port = $opts{listen_port} // 5000;
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
        $handler->($conn);
        $conn->close;
        POSIX::_exit(0);
    }
}

1;
