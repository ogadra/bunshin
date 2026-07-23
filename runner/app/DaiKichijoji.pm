use utf8;
package DaiKichijoji;
use strict;
use warnings;
use Fcntl qw(:flock O_RDWR O_CREAT);

my $COUNTER_PATH = $ENV{BUNSHIN_QUIZ_COUNTER} // '/tmp/bunshin-quiz-visits';

sub counter {
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

sub content {
    return qr{吉祥寺|大井町};
}

1;
