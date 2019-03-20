#!perl
use strict;
use Mojolicious::Lite;
use Mojolicious::Static;
use Cwd;
use YAML 'LoadFile', 'DumpFile';

plugin AutoReload => {};

unshift @{ app->static->paths }, getcwd;

get '/' => sub {
    my( $c ) = @_;
    $c->stash( files => [ map { s/\.joined.MP4//i; $_ } glob '*.joined.MP4' ]);
    $c->render( template => 'index' );
};

get '/<name>' => sub {
    my( $c ) = @_;
    my $file = $c->param('name');
    $c->stash( files => [ glob '*.joined.MP4' ]);
    $c->render( template => 'index' );
};

get '/video/<name>.joined.MP4' => sub {
    my( $c ) = @_;
    my $file = $c->param('name') . ".joined.MP4";
warn $file;
    $videos->serve($c, $file);
};
app->start;

__DATA__
@@index.html.ep
<html>
<body>
<ol>
%for my $file (@$files) {
<li><a href="<%= $file %>"><%=$file%></a></li>
%}
</ol>
</body>
</html>
