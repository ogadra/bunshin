use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use File::Temp qw(tempfile);
use lib "$FindBin::Bin/..";

my $COUNTER;
BEGIN {
    my ($fh, $path) = tempfile(UNLINK => 1); close $fh; unlink $path;
    $COUNTER = $path;
    $ENV{BUNSHIN_QUIZ_COUNTER} = $COUNTER;
}

use DaiKichijoji;

subtest 'counter: first visit creates the file and returns 1' => sub {
    ok !-e $COUNTER, 'no counter file before the first visit';
    is DaiKichijoji::counter(), 1;
    ok -e $COUNTER, 'counter file is created';
};

subtest 'counter: each visit increments the persisted count' => sub {
    is DaiKichijoji::counter(), 2;
    is DaiKichijoji::counter(), 3;
};

subtest 'counter: an empty existing file counts as the first visit' => sub {
    open my $fh, '>', $COUNTER or die "truncate $COUNTER: $!";
    close $fh;
    is DaiKichijoji::counter(), 1;
};

subtest 'counter: a corrupt (non-numeric) file dies instead of resetting' => sub {
    open my $fh, '>', $COUNTER or die "write $COUNTER: $!";
    print $fh 'not-a-number';
    close $fh;
    my $ok = eval { DaiKichijoji::counter(); 1 };
    ok !$ok, 'died';
    like $@, qr{corrupt counter file};
};

subtest 'counter: digits embedded in garbage still count as corrupt' => sub {
    open my $fh, '>', $COUNTER or die "write $COUNTER: $!";
    print $fh 'abc123';
    close $fh;
    my $ok = eval { DaiKichijoji::counter(); 1 };
    ok !$ok, 'died';
    like $@, qr{corrupt counter file};
};

subtest 'content: the shipped answer solves the quiz' => sub {
    require Quiz;
    my $matches = Quiz::evaluate(re => DaiKichijoji::content());
    is Quiz::judge(matches => $matches)->{status}, 'correct',
        'the initial regex judges correct against the real map';
};

done_testing;
