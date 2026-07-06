export const samplePerl = String.raw`#!/usr/bin/perl
use strict;
use warnings;

package Greeter;

=pod

Perl syntax highlight demo.

=cut

my $count = 1_000;
my @names = qw(alice bob carol);
my %seen;

sub greet {
    my ($name) = @_;
    my $message = <<~"EOF";
        Hello, $name!
        You are visitor number $count.
        EOF
    print $message;
}

foreach my $name (@names) {
    next if $seen{$name}++;
    greet($name);
}

my $csv = join(",", @names);
if ($csv =~ m/(\w+),(\w+)/) {
    print "first=$1 second=$2\n";
}

(my $upper = $csv) =~ tr/a-z/A-Z/;
my $ratio = $count / 2;
print q{done}, "\n";

__END__
Everything below is ignored.
`;
