use utf8;
package DaiKichijoji;
use strict;
use warnings;
use Fcntl qw(:flock O_RDWR O_CREAT);
use FindBin;
use lib "$FindBin::Bin";
use Quiz;

my $COUNTER_PATH = $ENV{BUNSHIN_QUIZ_COUNTER} // '/tmp/bunshin-quiz-visits';

sub content {
    my $visits = _tick();
    my $re = qr{吉祥寺|大井町};
    return Quiz::page(re => $re, visits => $visits);
}

sub _tick {
    sysopen(my $fh, $COUNTER_PATH, O_RDWR | O_CREAT, 0644)
        or die "open $COUNTER_PATH: $!\n";
    flock($fh, LOCK_EX) or die "flock $COUNTER_PATH: $!\n";
    my $n = do { local $/; <$fh> } // '';
    $n = ($n =~ /(\d+)/) ? $1 + 1 : 1;
    seek($fh, 0, 0);
    truncate($fh, 0);
    print $fh $n;
    close $fh;
    return $n;
}

1;
