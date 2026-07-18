package Bunshin::App;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Bunshin::HTTP;
use Module::Refresh;

my $HTML_SHELL = <<'HTML';
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>bunshin perl demo — 大吉祥寺.pm</title>
<style>
body { font-family: system-ui, sans-serif; margin: 2rem; line-height: 1.6; }
pre { background: #fee; padding: 1rem; border-radius: 4px; overflow: auto; }
</style>
</head>
<body>
%s
</body>
</html>
HTML

our $REFRESH_FN = sub { Module::Refresh->refresh };
our $CONTENT_FN = sub {
    my $sub = DaiKichijoji->can('content')
        or die "DaiKichijoji::content is not defined\n";
    $sub->();
};

# Module::Refresh の初回 refresh は %INC を "変更なし" として cache する
# だけで reload はしない。fork の後で子が初回 refresh を呼ぶと、その cache
# 化しかしないので、その後 disk が変わっても検知できない。親が accept
# ループに入る前に seed して、子は cache を継承した状態で refresh する
sub init {
    Module::Refresh->refresh;
}

sub handle_conn {
    my ($conn) = @_;

    my $drained = eval { Bunshin::HTTP::drain_request($conn); 1 };
    if (!$drained) {
        Bunshin::HTTP::respond($conn, 400, 'text/plain; charset=utf-8', "bad request: $@");
        return;
    }

    my $refreshed = eval { $REFRESH_FN->(); 1 };
    if (!$refreshed) {
        Bunshin::HTTP::respond($conn, 500, 'text/html; charset=utf-8', build_error_page("DaiKichijoji.pm load failed: $@"));
        return;
    }

    my $body;
    my $called = eval { $body = $CONTENT_FN->(); 1 };
    if (!$called) {
        Bunshin::HTTP::respond($conn, 500, 'text/html; charset=utf-8', build_error_page("DaiKichijoji::content died: $@"));
        return;
    }
    if (!defined $body) {
        Bunshin::HTTP::respond($conn, 500, 'text/html; charset=utf-8', build_error_page("DaiKichijoji::content returned undef"));
        return;
    }

    Bunshin::HTTP::respond($conn, 200, 'text/html; charset=utf-8', sprintf($HTML_SHELL, $body));
}

sub build_error_page {
    my ($msg) = @_;
    my $escaped = $msg;
    $escaped =~ s/&/&amp;/g;
    $escaped =~ s/</&lt;/g;
    $escaped =~ s/>/&gt;/g;
    return sprintf($HTML_SHELL, "<h1>Error</h1>\n<pre>$escaped</pre>");
}

1;
