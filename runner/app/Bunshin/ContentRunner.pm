package Bunshin::ContentRunner;
use strict;
use warnings;
use POSIX ();
use Carp ();

use constant {
    TAG_OK  => 'C',
    TAG_ERR => 'E',
};

sub run {
    my (%opts) = @_;
    my $content_fn = $opts{content_fn}
        // return { status => 'died', error => "content_fn required\n" };

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
    my $payload = do { local $/; <$reader> };
    close $reader;

    waitpid $pid, 0;
    my $status    = $?;
    my $signal    = $status & 0x7f;
    my $exit_code = $status >> 8;

    return { status => 'died', error => "killed by signal $signal\n" } if $signal;

    my $tag  = defined $payload && length $payload      ? substr($payload, 0, 1) : '';
    my $body = defined $payload && length $payload > 1  ? substr($payload, 1)    : '';

    return { status => 'ok',     body  => $body } if $exit_code == 0 && $tag eq TAG_OK;
    return { status => 'died',   error => $body } if $exit_code == 1 && $tag eq TAG_ERR;
    return { status => 'exited', code  => $exit_code };
}

sub _run_child {
    my ($writer, $content_fn) = @_;

    local $SIG{PIPE} = 'IGNORE';

    my $body;
    my $ok = eval {
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

1;
