use strict;
use warnings;

return sub {
    my ($method, $path, $body) = @_;
    my $html = <<'HTML';
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>bunshin perl demo</title>
<style>
body { font-family: system-ui, sans-serif; margin: 2rem; }
code { background: #f4f4f4; padding: 0.1rem 0.3rem; border-radius: 3px; }
</style>
</head>
<body>
<h1>Hello from handler.pl</h1>
<p>Edit <code>runner/app/handler.pl</code> in the editor to change this page.</p>
</body>
</html>
HTML
    return (200, 'text/html; charset=utf-8', $html);
};
