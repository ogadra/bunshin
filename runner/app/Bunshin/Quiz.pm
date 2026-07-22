package Bunshin::Quiz;
use strict;
use warnings;
use utf8;
use Encode ();
use Fcntl qw(:flock O_RDWR O_CREAT);
use HTML::Entities ();
use re qw(regexp_pattern);

our $MAP = join "\n",
    '吉祥寺井の頭公園三鷹台久我山高井戸浜田山西永福永福町明大前下北沢神泉渋谷',
    '渋谷恵比寿大崎',
    '大崎大井町',
    '大井町品川高輪ゲートウェイ田町浜松町新橋有楽町東京',
    '東京神田御茶ノ水四ツ谷新宿中野高円寺阿佐ケ谷荻窪西荻窪吉祥寺';

our $ANSWER = { '吉祥寺' => 1, '大井町' => 1 };
our $RECORD_PATH = $ENV{BUNSHIN_QUIZ_RECORD} // '/tmp/bunshin-quiz-record';

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

sub update_record {
    my (%opts) = @_;
    my $status = $opts{status} // die "status required\n";
    my $visits = $opts{visits} // die "visits required\n";
    my $bytes  = $opts{bytes}  // die "bytes required\n";
    my $path   = $opts{path}   // $RECORD_PATH;

    sysopen(my $fh, $path, O_RDWR | O_CREAT, 0644) or die "open $path: $!\n";
    flock($fh, LOCK_EX) or die "flock $path: $!\n";
    my $content = do { local $/; <$fh> } // '';
    my ($first, $best) = (0, 0);
    if ($content =~ /^first_correct_visit=(\d+)$/m) { $first = $1 + 0 }
    if ($content =~ /^best_bytes=(\d+)$/m)          { $best  = $1 + 0 }

    if ($status eq 'correct') {
        $first = $visits if !$first;
        $best  = $bytes  if !$best || $bytes < $best;
    }

    seek($fh, 0, 0);
    truncate($fh, 0);
    print $fh "first_correct_visit=$first\nbest_bytes=$best\n";
    close $fh;
    return { first_correct_visit => $first, best_bytes => $best };
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
    my $path   = $opts{record_path} // $RECORD_PATH;

    my $rd      = regex_display($re);
    my $matches = evaluate(re => $re);
    my $judged  = judge(matches => $matches);
    my $rec     = update_record(
        status => $judged->{status},
        visits => $visits,
        bytes  => $rd->{bytes},
        path   => $path,
    );

    my $counter = sprintf('%07d', $visits);
    my $kir     = kirban($visits);
    my $kir_html = defined $kir ? ' <em class="kirban">' . _esc($kir) . '</em>' : '';
    my $map_html = highlight_map(matches => $matches);
    my $re_html  = _esc($rd->{source});
    my $msg_html = _esc($judged->{message});
    my $first    = $rec->{first_correct_visit} || '—';
    my $best     = $rec->{best_bytes}          || '—';

    return <<~"HTML";
        <h1>大吉祥寺.pm平成CGI</h1>
        <section class="counter">
          <p>アクセス数: <strong>$counter</strong>$kir_html</p>
        </section>
        <section class="quiz">
          <h2>問題</h2>
          <p>この往復記録に<strong>2回</strong>現れる、漢字3文字の駅を抜き出せ。</p>
          <pre class="map">$map_html</pre>
          <p>正規表現: <code>$re_html</code> ($rd->{bytes} bytes)</p>
          <p class="verdict verdict-$judged->{status}">$msg_html</p>
        </section>
        <section class="record">
          <h2>記録</h2>
          <p>初正解: 訪問 #$first</p>
          <p>最短バイト: $best</p>
        </section>
        HTML
}

1;
