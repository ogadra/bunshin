package Bunshin::App;
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Bunshin::ContentRunner;
use Bunshin::HTTP;
use HTML::Entities ();
use Module::Refresh;

my $HTML_SHELL = <<~'HTML';
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>bunshin perl demo: 大吉祥寺.pm</title>
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

my $CONTENT_FN = sub {
    my $sub = DaiKichijoji->can('content')
        or die "DaiKichijoji::content is not defined\n";
    $sub->();
};
our $RUN_CONTENT_FN = sub {
    unless (eval { Module::Refresh->refresh; 1 }) {
        die "DaiKichijoji.pm load failed: $@";
    }
    return Bunshin::ContentRunner::run(
        content_fn => $CONTENT_FN,
        timeout_ms => 3000,
    );
};

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

    my $result = eval { $RUN_CONTENT_FN->() };
    if (!$result || ref $result ne 'HASH') {
        respond_error($conn, $@ || "content runner returned no result");
        return;
    }

    for ($result->{status}) {
        if ($_ eq 'ok') {
            Bunshin::HTTP::respond($conn, 200, 'text/html; charset=utf-8', sprintf($HTML_SHELL, HTML::Entities::encode_entities($result->{body})));
        } elsif ($_ eq 'died') {
            respond_error($conn, "DaiKichijoji::content died: $result->{error}");
        } elsif ($_ eq 'exited') {
            respond_error($conn, "DaiKichijoji::content exited with code $result->{code}");
        } elsif ($_ eq 'timed_out') {
            respond_error($conn, "DaiKichijoji::content timed out: exceeded $result->{ms}ms");
        } else {
            respond_error($conn, "content runner returned unknown status: $_");
        }
    }
}

sub respond_error {
    my ($conn, $msg) = @_;
    Bunshin::HTTP::respond($conn, 500, 'text/html; charset=utf-8', build_error_page($msg));
}

sub build_error_page {
    my ($msg) = @_;
    my $escaped = HTML::Entities::encode_entities($msg);
    return sprintf($HTML_SHELL, "<h1>Error</h1>\n<pre>$escaped</pre>");
}

1;
