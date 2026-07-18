use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use Bunshin::ContentRunner;
use POSIX ();
use Time::HiRes ();

$SIG{ALRM} = sub { die "test watchdog: hang detected\n" };
alarm 30;

subtest 'ok: content is passed through as bytes' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub { "hello" });
    is $r->{status}, 'ok';
    is $r->{body},   'hello';
};

subtest 'ok: utf8-flagged content is encoded before pipe transfer' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub {
        my $s = "\x{3042}\x{3044}";
        utf8::upgrade($s);
        return $s;
    });
    is $r->{status}, 'ok';
    is $r->{body}, "\xe3\x81\x82\xe3\x81\x84", 'utf8 bytes on the wire';
};

subtest 'died: die captured with longmess stack trace' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub { die "boom\n" });
    is $r->{status}, 'died';
    like $r->{error}, qr{boom};
    like $r->{error}, qr{Bunshin::ContentRunner}, 'stack trace present';
};

subtest 'died: content returning undef reported as died' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub { undef });
    is $r->{status}, 'died';
    like $r->{error}, qr{returned undef};
};

subtest 'exited: exit(42) captured as exit code' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub { exit 42 });
    is $r->{status}, 'exited';
    is $r->{code},   42;
};

subtest 'exited: exit(0) distinguished from ok because tag is missing' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub { exit 0 });
    is $r->{status}, 'exited';
    is $r->{code},   0;
};

subtest 'exited: POSIX::_exit(7) also captured' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub { POSIX::_exit(7) });
    is $r->{status}, 'exited';
    is $r->{code},   7;
};

subtest 'died: uncatchable signal reported as killed by signal' => sub {
    my $r = Bunshin::ContentRunner::run(content_fn => sub {
        kill 'KILL', $$;
        sleep 5;
        "unreachable";
    });
    is $r->{status}, 'died';
    like $r->{error}, qr{killed by signal 9};
};

subtest 'died: fork survives against parent SIG{CHLD} = IGNORE' => sub {
    local $SIG{CHLD} = 'IGNORE';
    my $r = Bunshin::ContentRunner::run(content_fn => sub { "post-ignore" });
    is $r->{status}, 'ok', 'ContentRunner locally overrides CHLD so waitpid works';
    is $r->{body}, 'post-ignore';
};

subtest 'timed_out: content exceeding budget is cut off before it finishes' => sub {
    my $t0 = Time::HiRes::time();
    my $r  = Bunshin::ContentRunner::run(
        content_fn => sub { sleep 5; "unreachable" },
        timeout_ms => 200,
    );
    my $elapsed_ms = (Time::HiRes::time() - $t0) * 1000;
    is $r->{status}, 'timed_out';
    is $r->{ms},     200;
    cmp_ok $elapsed_ms, '<', 2000, 'returned well before content would have finished';
};

subtest 'timed_out: fires even when parent has SIG{ALRM} = IGNORE (select-based watchdog)' => sub {
    local $SIG{ALRM} = 'IGNORE';
    my $r = Bunshin::ContentRunner::run(
        content_fn => sub { sleep 5; "unreachable" },
        timeout_ms => 200,
    );
    is $r->{status}, 'timed_out', 'select timeout does not rely on SIGALRM';
};

subtest 'timed_out: fires even when content sets SIG{ALRM} = IGNORE inside the grandchild' => sub {
    my $r = Bunshin::ContentRunner::run(
        content_fn => sub { $SIG{ALRM} = 'IGNORE'; sleep 5; "unreachable" },
        timeout_ms => 200,
    );
    is $r->{status}, 'timed_out', 'SIGKILL from parent bypasses in-child signal handling';
};

subtest 'ok: fast content finishes before the timeout budget' => sub {
    my $r = Bunshin::ContentRunner::run(
        content_fn => sub { "quick" },
        timeout_ms => 3000,
    );
    is $r->{status}, 'ok';
    is $r->{body},   'quick';
};

subtest 'exited: user exit(42) still classifies as exited even with a timeout set' => sub {
    my $r = Bunshin::ContentRunner::run(
        content_fn => sub { exit 42 },
        timeout_ms => 3000,
    );
    is $r->{status}, 'exited';
    is $r->{code},   42;
};

subtest 'died: missing content_fn returns died' => sub {
    my $r = Bunshin::ContentRunner::run();
    is $r->{status}, 'died';
    like $r->{error}, qr{content_fn required};
};

alarm 0;
done_testing;
