package Bunshin::ContentRunner;
use strict;
use warnings;
use POSIX ();
use Carp ();
use Time::HiRes ();

use constant {
    TAG_OK  => 'C',
    TAG_ERR => 'E',
};

sub run {
    my (%opts) = @_;
    my $content_fn = $opts{content_fn}
        // Carp::croak 'content_fn required';
    my $timeout_ms = $opts{timeout_ms};

    local $SIG{CHLD} = 'DEFAULT';

    pipe(my $reader, my $writer)
        or return { status => 'died', error => "pipe: $!\n" };

    my $pid = fork();
    if (!defined $pid) {
        close $reader;
        close $writer;
        return { status => 'died', error => "fork: $!\n" };
    }

    if ($pid == 0) {
        close $reader;
        _run_child($writer, $content_fn);
    }

    close $writer;
    my ($payload, $timed_out) = _read_payload($reader, $timeout_ms);
    close $reader;

    kill 'KILL', $pid if $timed_out;
    waitpid $pid, 0;
    my $status    = $?;
    my $signal    = $status & 0x7f;
    my $exit_code = $status >> 8;

    return { status => 'timed_out', ms => $timeout_ms } if $timed_out;
    return { status => 'died', error => "killed by signal $signal\n" } if $signal;

    my $tag  = defined $payload && length $payload      ? substr($payload, 0, 1) : '';
    my $body = defined $payload && length $payload > 1  ? substr($payload, 1)    : '';

    return { status => 'ok',     body  => $body } if $exit_code == 0 && $tag eq TAG_OK;
    return { status => 'died',   error => $body } if $exit_code == 1 && $tag eq TAG_ERR;
    return { status => 'exited', code  => $exit_code };
}

sub _read_payload {
    my ($reader, $timeout_ms) = @_;

    return (scalar do { local $/; <$reader> }, 0) unless defined $timeout_ms;

    my $mask = '';
    vec($mask, fileno($reader), 1) = 1;
    my $deadline = Time::HiRes::time() + $timeout_ms / 1000;
    my $payload  = '';

    while (1) {
        my $remaining = $deadline - Time::HiRes::time();
        return ($payload, 1) if $remaining <= 0;

        my $ready = select(my $rout = $mask, undef, undef, $remaining);
        return ($payload, 1) if !$ready;

        my $chunk;
        my $n = sysread($reader, $chunk, 65536);
        return ($payload, 0) unless $n;
        $payload .= $chunk;
    }
}

sub _run_child {
    my ($writer, $content_fn) = @_;

    local $SIG{PIPE} = 'IGNORE';
    $SIG{__WARN__} = sub {
        return if $_[0] =~ /Bad file descriptor during global destruction/;
        warn $_[0];
    };

    my $body;
    my $ok = eval {
        _close_inherited_fds(fileno($writer));
        local $SIG{__DIE__} = sub { die Carp::longmess($_[0]) };
        $body = $content_fn->();
        die "content returned undef\n" unless defined $body;
        1;
    };

    if ($ok) {
        utf8::encode($body) if utf8::is_utf8($body);
        print $writer TAG_OK, $body;
        close $writer;
        POSIX::_exit(0);
    }

    my $err = $@;
    utf8::encode($err) if utf8::is_utf8($err);
    print $writer TAG_ERR, $err;
    close $writer;
    POSIX::_exit(1);
}

sub _close_inherited_fds {
    my ($keep_fd) = @_;
    opendir(my $dh, '/proc/self/fd')
        or die "cannot open /proc/self/fd: $!\n";
    my $dh_fd = fileno($dh);
    my @to_close;
    while (my $entry = readdir $dh) {
        next unless $entry =~ /\A(\d+)\z/;
        my $fd = 0 + $1;
        next if $fd < 3 || $fd == $keep_fd || $fd == $dh_fd;
        push @to_close, $fd;
    }
    closedir $dh;
    POSIX::close($_) for @to_close;
}

1;
