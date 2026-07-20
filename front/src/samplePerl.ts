export const samplePerl = String.raw`package DaiKichijoji;
use strict;
use warnings;

=pod

Edit sub content to change the page rendered in the preview iframe.
The HTML shell around the returned string lives in Bunshin/App.pm.

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
