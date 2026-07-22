use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../..";
use Quiz;

binmode Test::More->builder->$_, ':encoding(UTF-8)'
    for qw(output failure_output todo_output);

subtest 'MAP: 3-char windows repeat only for 吉祥寺 and 大井町' => sub {
    my %count;
    my $len = length $Quiz::MAP;
    for my $i (0 .. $len - 3) {
        my $window = substr($Quiz::MAP, $i, 3);
        next if $window =~ /\n/;
        $count{$window}++;
    }
    my @repeated = sort grep { $count{$_} >= 2 } keys %count;
    is_deeply \@repeated, ['吉祥寺', '大井町'],
        'only 吉祥寺 and 大井町 repeat among all 3-char (no-newline) windows';
};

subtest 'evaluate: literal 吉祥寺|大井町 picks up both stations' => sub {
    my $matches = Quiz::evaluate(re => qr{吉祥寺|大井町});
    my %set = map { $_->{pick} => 1 } @$matches;
    is_deeply [sort keys %set], ['吉祥寺', '大井町'], 'match set = expected';
    cmp_ok scalar(@$matches), '>=', 4, 'both stations matched twice';
};

subtest 'evaluate: greedy /s backref consumes the whole string in one match' => sub {
    my $matches = Quiz::evaluate(re => qr{(...).*\1}s);
    my %set = map { $_->{pick} => 1 } @$matches;
    is scalar(@$matches), 1, 'greedy .* leaves nothing for a second iteration';
    is_deeply [sort keys %set], ['吉祥寺'], 'only the outermost pair is picked';
};

subtest 'evaluate: /s lookahead backref captures both stations' => sub {
    my $matches = Quiz::evaluate(re => qr{(...)(?=.*\1)}s);
    my %set = map { $_->{pick} => 1 } @$matches;
    is_deeply [sort keys %set], ['吉祥寺', '大井町'], 'captures fill the answer set';
};

subtest 'evaluate: no /s + backref finds nothing (dot skips newline)' => sub {
    my $matches = Quiz::evaluate(re => qr{(...).*\1});
    is scalar(@$matches), 0, 'no cross-line matches';
};

subtest 'evaluate: (...)\n\1 captures only the adjacent-line pair (大井町)' => sub {
    my $matches = Quiz::evaluate(re => qr{(...)\n\1});
    my %set = map { $_->{pick} => 1 } @$matches;
    is_deeply [sort keys %set], ['大井町'], 'the 3-char neighbour is 大井町';
};

subtest 'evaluate: /^...|...$/ picks up 吉祥寺 only (both string ends)' => sub {
    my $matches = Quiz::evaluate(re => qr{^...|...$});
    my %set = map { $_->{pick} => 1 } @$matches;
    is_deeply [sort keys %set], ['吉祥寺'], 'only 吉祥寺 at the string ends';
};

subtest 'judge: stage 1 (literal) is correct' => sub {
    my $m = Quiz::evaluate(re => qr{吉祥寺|大井町});
    my $v = Quiz::judge(matches => $m);
    is $v->{status}, 'correct';
};

subtest 'judge: /s lookahead backref is correct' => sub {
    my $m = Quiz::evaluate(re => qr{(...)(?=.*\1)}s);
    my $v = Quiz::judge(matches => $m);
    is $v->{status}, 'correct';
};

subtest 'judge: matching only 吉祥寺 is wrong' => sub {
    my $m = Quiz::evaluate(re => qr{(...).*\1}s);
    my $v = Quiz::judge(matches => $m);
    is $v->{status}, 'wrong';
};

subtest 'judge: matching only 大井町 is wrong' => sub {
    my $m = Quiz::evaluate(re => qr{(...)\n\1});
    my $v = Quiz::judge(matches => $m);
    is $v->{status}, 'wrong';
};

subtest 'judge: no matches is wrong' => sub {
    my $m = Quiz::evaluate(re => qr{ZZZZ});
    my $v = Quiz::judge(matches => $m);
    is $v->{status}, 'wrong';
};

subtest 'judge: unexpected match set is wrong' => sub {
    my $m = Quiz::evaluate(re => qr{渋谷});
    my $v = Quiz::judge(matches => $m);
    is $v->{status}, 'wrong';
};

subtest 'regex_display: literal answer weighs 19 bytes' => sub {
    my $rd = Quiz::regex_display(qr{吉祥寺|大井町});
    is $rd->{bytes}, 19, '3 kanji x 6 + | = 19 bytes';
    is $rd->{mods}, '', 'implicit /u is hidden';
};

subtest 'regex_display: /s backref answer weighs 11 bytes' => sub {
    my $rd = Quiz::regex_display(qr{(...).*\1}s);
    is $rd->{bytes}, 11, 'pattern (9) + /s (2) = 11';
    is $rd->{mods}, 's';
};

subtest 'kirban: multiples of 100 and repunit visits get 大吉' => sub {
    is Quiz::kirban(100), '大吉 (100の倍数)';
    is Quiz::kirban(555), '大吉 (ゾロ目)';
    is Quiz::kirban(11), undef, 'two-digit repdigit is not 大吉';
    is Quiz::kirban(42), undef;
};

subtest 'highlight_map: matched spans are wrapped in <mark>' => sub {
    my $m = Quiz::evaluate(re => qr{吉祥寺|大井町});
    my $html = Quiz::highlight_map(matches => $m);
    like $html, qr{<mark>吉祥寺</mark>};
    like $html, qr{<mark>大井町</mark>};
    unlike $html, qr{<mark></mark>}, 'no empty marks';
};

subtest 'highlight_map: HTML metacharacters in the map are escaped' => sub {
    local $Quiz::MAP = 'abc<xy>&"z';
    my $m = Quiz::evaluate(re => qr{abc});
    my $html = Quiz::highlight_map(matches => $m);
    like $html, qr{&lt;xy&gt;},   '< > escaped';
    like $html, qr{&amp;},        '& escaped';
    like $html, qr{&quot;},       '" escaped';
    unlike $html, qr{<xy>},       'raw tag not present';
};

subtest 'page: HTML metacharacters in the regex source are escaped' => sub {
    my $html = Quiz::page(re => qr{<script>}, visits => 1);
    like $html, qr{&lt;script&gt;}, 'user-supplied regex is escaped';
    unlike $html, qr{<script>},     'raw regex not embedded';
};

subtest 'evaluate: zero-width lookahead scan terminates and advances' => sub {
    local $Quiz::MAP = 'aXaXa';
    my $matches = Quiz::evaluate(re => qr{(?=a)});
    is scalar(@$matches), 3, 'one zero-width hit per a';
    is_deeply [map { $_->{start} } @$matches], [0, 2, 4], 'positions advance';
};

subtest 'required opts: subs die when a critical arg is missing' => sub {
    my @cases = (
        [sub { Quiz::evaluate() },       qr{re required} ],
        [sub { Quiz::judge() },          qr{matches required} ],
        [sub { Quiz::highlight_map() },  qr{matches required} ],
        [sub { Quiz::page() },           qr{re required} ],
        [sub { Quiz::page(re => qr{x}) },qr{visits required} ],
    );
    for my $c (@cases) {
        my ($fn, $pat) = @$c;
        my $ok = eval { $fn->(); 1 };
        ok !$ok, 'died';
        like $@, $pat, "matches $pat";
    }
};

subtest 'page: renders counter, question, and verdict' => sub {
    my $html = Quiz::page(re => qr{吉祥寺|大井町}, visits => 42);
    like $html, qr{アクセス数.*0000042}s, 'counter is 7-digit zero padded';
    like $html, qr{2回}, 'question copy present';
    like $html, qr{verdict-correct}, 'verdict class reflects status';
};

done_testing;
