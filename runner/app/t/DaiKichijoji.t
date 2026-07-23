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

binmode Test::More->builder->$_, ':encoding(UTF-8)'
    for qw(output failure_output todo_output);

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

subtest 'counter: a symlinked counter path dies instead of writing through' => sub {
    unlink $COUNTER;
    my ($fh, $target) = tempfile(UNLINK => 1);
    close $fh;
    symlink $target, $COUNTER or die "symlink $COUNTER: $!";
    my $ok = eval { DaiKichijoji::counter(); 1 };
    ok !$ok, 'died';
    like $@, qr{open \Q$COUNTER\E}, 'O_NOFOLLOW refuses the symlink';
    unlink $COUNTER;
};

subtest 'content: the initial answer catches line-crossing repeats but misses 吉祥寺' => sub {
    require Quiz;
    my $matches = Quiz::evaluate(re => DaiKichijoji::content());
    my %set = map { $_->{pick} => 1 } @$matches;
    is_deeply [sort keys %set], ['大井町', '東京', '渋谷'],
        '吉祥寺 at the string ends is not adjacent across lines';
    is Quiz::judge(matches => $matches)->{status}, 'wrong',
        'participants still have to narrow the answer down';
};

done_testing;
