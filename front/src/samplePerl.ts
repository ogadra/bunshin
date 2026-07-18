export const samplePerl = String.raw`package DaiKichijoji;
use strict;
use warnings;

=pod

Edit sub content to change the page rendered at http://127.0.0.1:5000/.
The HTML shell around the returned string lives in BunshinServer.pm.

=cut

my $count = 42;
my @names = qw(alice bob carol);

sub content {
    my $greeting = "Hello from DaiKichijoji.pm";
    if ($greeting =~ m/(\w+)\s+from/) {
        print "matched: $1\n";
    }
    return join(" — ", $greeting, "count=$count", "names=" . scalar(@names));
}

1;
`;
