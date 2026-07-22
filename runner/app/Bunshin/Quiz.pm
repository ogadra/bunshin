package Bunshin::Quiz;
use strict;
use warnings;
use utf8;
use Encode ();
use HTML::Entities ();
use re qw(regexp_pattern);

our $MAP = join "\n",
    '吉祥寺久我山永福町明大前下北沢渋谷',
    '渋谷恵比寿大崎大井町',
    '大井町品川高輪ゲートウェイ田町浜松町新橋有楽町東京',
    '東京神田御茶ノ水四ツ谷新宿中野荻窪吉祥寺';

our $ANSWER = { '吉祥寺' => 1, '大井町' => 1 };

my $UNSAFE_HTML = '<>&"';

sub _esc { HTML::Entities::encode_entities($_[0], $UNSAFE_HTML) }

sub evaluate {
    my (%opts) = @_;
    my $re  = $opts{re} // die "re required\n";
    my $map = $MAP;

    my @matches;
    while ($map =~ /$re/g) {
        my $whole = substr($map, $-[0], $+[0] - $-[0]);
        my $pick  = defined $1 ? $1 : $whole;
        push @matches, {
            pick  => $pick,
            whole => $whole,
            start => $-[0],
            end   => $+[0],
        };
        pos($map) = $+[0] + 1 if $+[0] == $-[0];
    }
    return \@matches;
}

sub judge {
    my (%opts) = @_;
    my $matches = $opts{matches} // die "matches required\n";
    my %set = map { $_->{pick} => 1 } @$matches;
    my $expected = join '|', sort keys %$ANSWER;
    my $actual   = join '|', sort keys %set;

    return { status => 'correct', message => '正解！家に帰り着きました。' }
        if $actual eq $expected;
    if (keys(%set) == 1 && $set{'吉祥寺'}) {
        return { status => 'partial', message => '家から出ていません。' };
    }
    if (keys(%set) == 1 && $set{'大井町'}) {
        return { status => 'partial', message => '帰りの電車がありません。' };
    }
    my $msg = @$matches ? '不正解。答えは漢字3文字の駅、2つ。' : '不正解。ヒットなし。';
    return { status => 'wrong', message => $msg };
}

sub regex_display {
    my ($re) = @_;
    my ($pat, $mods) = regexp_pattern($re);
    $mods =~ tr/u//d;
    my $src = length $mods ? "$pat/$mods" : $pat;
    my $bytes = Encode::encode('UTF-8', $src);
    return { pattern => $pat, mods => $mods, source => $src, bytes => length $bytes };
}

sub highlight_map {
    my (%opts) = @_;
    my $matches = $opts{matches} // die "matches required\n";
    my $map     = $MAP;
    my @sorted  = sort { $a->{start} <=> $b->{start} } @$matches;

    my ($out, $cursor) = ('', 0);
    for my $m (@sorted) {
        next if $m->{start} < $cursor;
        $out .= _esc(substr($map, $cursor, $m->{start} - $cursor));
        $out .= '<mark>' . _esc($m->{whole}) . '</mark>';
        $cursor = $m->{end};
    }
    $out .= _esc(substr($map, $cursor));
    return $out;
}

sub kirban {
    my ($visits) = @_;
    return unless $visits > 0;
    return '大吉 (100の倍数)' if $visits % 100 == 0;
    my $s = "$visits";
    return '大吉 (ゾロ目)' if length($s) >= 3 && $s =~ /^(.)\1+$/;
    return;
}

sub page {
    my (%opts) = @_;
    my $re     = $opts{re}     // die "re required\n";
    my $visits = $opts{visits} // die "visits required\n";

    my $rd      = regex_display($re);
    my $matches = evaluate(re => $re);
    my $judged  = judge(matches => $matches);

    my $counter = sprintf('%07d', $visits);
    my $kir     = kirban($visits);
    my $kir_html = defined $kir ? ' <em class="kirban">' . _esc($kir) . '</em>' : '';
    my $map_html = highlight_map(matches => $matches);
    my $re_html  = _esc($rd->{source});
    my $msg_html = _esc($judged->{message});

    return <<~"HTML";
        <h1>Perl 正規表現クイズ!</h1>
        <section class="counter">
          <p>アクセス数: <strong>$counter</strong>$kir_html</p>
        </section>
        <section class="quiz">
          <h2>問題</h2>
          <p>
            たかし君は最寄り駅から電車に乗って、下記の駅に停車しながら最寄り駅まで戻りました。<br/>
            ただし、乗り換えに使用した駅は2回表示されています。
          </p>
          <pre class="map">$map_html</pre>
          <p>
            たかし君が乗り換えに使用した駅の中で、漢字3文字の駅はどれですか？<br/>
            正規表現で抜き出して解答してください。
          </p>
          <p>正規表現: <code>$re_html</code> ($rd->{bytes} bytes)</p>
          <p class="verdict verdict-$judged->{status}">$msg_html</p>
        </section>
        HTML
}

1;
