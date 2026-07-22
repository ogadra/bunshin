use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use File::Temp qw(tempfile);

BEGIN {
    my ($fh1, $counter) = tempfile(UNLINK => 1); close $fh1; unlink $counter;
    $ENV{BUNSHIN_QUIZ_COUNTER} = $counter;
}

use lib "$FindBin::Bin/..";
use DaiKichijoji;

sub reset_counter { unlink $ENV{BUNSHIN_QUIZ_COUNTER} }
sub seed_counter  { my ($v) = @_; open my $fh, '>', $ENV{BUNSHIN_QUIZ_COUNTER} or die $!; print $fh $v; close $fh }

subtest '_tick starts at 1 and increments on every call' => sub {
    reset_counter();
    is DaiKichijoji::_tick(), 1, 'first call sees an empty file and writes 1';
    is DaiKichijoji::_tick(), 2, 'second call reads 1 and writes 2';
    is DaiKichijoji::_tick(), 3, 'third call reads 2 and writes 3';
};

subtest '_tick recovers from a non-numeric counter file by resetting to 1' => sub {
    seed_counter('corrupted stuff');
    is DaiKichijoji::_tick(), 1, 'garbage payload restarts the count';
    is DaiKichijoji::_tick(), 2, 'and continues from there';
};

subtest '_tick parses a numeric prefix from mixed content' => sub {
    seed_counter('42abc');
    is DaiKichijoji::_tick(), 43, 'the leading integer wins';
};

done_testing;
