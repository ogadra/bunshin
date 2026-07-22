use utf8;
package DaiKichijoji;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";
use Quiz;

sub content {
    return Quiz::page(re => qr{吉祥寺|大井町});
}

1;
