use utf8;
package DaiKichijoji;
use strict;
use warnings;
use Fcntl qw(:flock O_RDWR O_CREAT O_NOFOLLOW);

my $COUNTER_PATH = $ENV{BUNSHIN_QUIZ_COUNTER} // '/tmp/bunshin-quiz-visits';

sub counter {
    sysopen(my $fh, $COUNTER_PATH, O_RDWR | O_CREAT | O_NOFOLLOW, 0600)
        or die "open $COUNTER_PATH: $!\n";
    flock($fh, LOCK_EX) or die "flock $COUNTER_PATH: $!\n";
    my $n = do { local $/; <$fh> } // '';
    $n =~ /\A\d*\z/ or die "corrupt counter file $COUNTER_PATH\n";
    $n++;
    seek $fh, 0, 0;
    truncate $fh, 0;
    print $fh $n;
    return $n;
}

sub content {
    return qr{(\S+)\n\1}s;
}

1;
