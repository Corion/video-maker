#!perl
use strict;
use Mojolicious::Lite;
use Mojolicious::Static;
use Mojo::Util 'url_escape', 'url_unescape', 'decode';
use Cwd;
use YAML 'LoadFile', 'DumpFile';
use File::Basename;

plugin AutoReload => {};

unshift @{ app->static->paths }, getcwd;

my $config;
if( ! $ENV{CONFIG}) {
    die "No CONFIG= given!";
};

open my $fh, '<', $ENV{CONFIG}
    or die "Couldn't read config file '$ENV{CONFIG}'";
my %config = map { /^\s*([^#].*?)=(.*)/ ? ($1 => $2) : () } <$fh>;

app->types->type( MP4 => 'video/mp4' );
app->types->type( mkv => 'video/webm' );

sub video_file {
    my ($fn) = @_;
    return $config{VIDEO} . '/' . $fn;
}

sub yaml_file {
    my ($fn) = @_;
    return $config{VIDEO} . '/' . $fn;
}

get '/' => sub {
    my( $c ) = @_;
    my $files = [ map { s/\.joined.(mkv|MP4)$//i; { file => encode_name(basename($_)), name => decode('UTF-8', $_) } } glob $config{VIDEO} . '/*.joined.{MP4,mkv}' ];
    $c->stash( files => $files);
    $c->render( template => 'index' );
};

sub decode_name {
    my( $name ) = @_;
    return url_unescape($name)
}
sub encode_name {
    my( $name ) = @_;
    return url_escape($name)
}

get '/video/<name>.joined.<ext>' => sub {
    my( $c ) = @_;
    my $ext = $c->param('ext');
    return unless $ext =~ /^(MP4|mkv)$/i;
    my $file = video_file( decode_name($c->param('name')) . ".joined.$ext" );
    $c->reply->static( $file );
};

get '/cut/<name>' => sub {
    my( $c ) = @_;
    my $file = $config{VIDEO} .'/'. decode_name($c->param('name')) . ".joined.";
    (my $ext) = grep { -f $file . $_ } (qw(MP4 mkv));

    return unless $ext;
    $file .= $ext;

    my $info = yaml_file(decode_name($c->param('name')) . '.yml');
    $info = LoadFile( $info );
    $c->stash( file => basename($file), %$info  );
    $c->render( template => 'cut' );
};

post '/cut/<name>' => sub {
    my( $c ) = @_;
    my $file = $config{VIDEO} .'/'. decode_name($c->param('name')) . ".joined.";
    (my $ext) = grep { -f $file . $_ } (qw(MP4 mkv));
    return unless $ext;
    $file .= $ext;
    my $yml = yaml_file(decode_name($c->param('name')) . '.yml');
    my $info = {
        start => $c->param('start'),
        stop  => $c->param('stop'),
        metadata => {
            title => $c->param('title'),
            artist => $c->param('artist'),
            show   => $c->param('show'),
            language => $c->param('language'),
            url  => $c->param('url'),
        },
    };
    DumpFile( $yml, $info );
    $c->redirect_to($c->url_for('/cut/' . decode_name($c->param('name'))));
};

app->start;

__DATA__
@@index.html.ep
<!DOCTYPE html>
<html lang="en">
<meta charset="utf-8"/>
<body>
<ol>
%for my $file (@$files) {
<li><a href="/cut/<%= $file->{file} %>"><%=$file->{name}%></a></li>
%}
</ol>
</body>
</html>

@@app.css
video { width: 100% }

@@cut.html.ep
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<link rel="stylesheet"  type="text/css" href="/app.css" />
<script>
var video;
var playUntil;

function saveForm(e) {
    var http = new XMLHttpRequest();
    var url = window.location;
    var params = [];

    var inputs = document.querySelectorAll("input[value]");
    for( var el = 0; el < inputs.length; el++ ) {
        params.push(encodeURIComponent(inputs[el].name) + '=' + encodeURIComponent(inputs[el].value))
    };
    var payload = params.join('&').replace(/%20/g, '+');

    http.open('POST', url, true);
    http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

    http.onreadystatechange = function() {
        if(http.readyState == 4 && http.status == 200) {
            // everything went OK
        }
    }
    http.send(payload);

    e.preventDefault();
    return false;
}

function ready() {
    video = document.getElementById("myvideo");
    video.addEventListener('timeupdate', function() {
        document.getElementById("timer").innerHTML = to_ts( video.currentTime );
        if( playUntil && video.currentTime >= playUntil ) {
            video.pause();
            playUntil = undefined;
        };
    });
    btnSave = document.getElementById("btnSave");
    btnSave.addEventListener('click', saveForm );

    document.addEventListener('keydown', function(e) {
        e = e || window.event;
        if( e.target.tagName == "INPUT" ) return;
        var charCode = e.which || e.keyCode;

        // I -> go back to index page
        if(charCode == 73) {
            var indexPage = document.getElementById("lnkIndex");
            window.location.assign( indexPage.href );
        };

        // F -> save the current state
        if(charCode == 70) {
            saveForm({});
        };

        if(charCode == 32) { if (video.paused) { video.play() } else { video.pause() }};
        // Q -> step back a second
        if(charCode == 81) { stepff('',-1 * (e.shiftKey ? 0.1 : 1 ))};
        // E -> step forward a second
        if(charCode == 69) { stepff('',+1 * (e.shiftKey ? 0.1 : 1 ))};

        // S -> Use as start timestamp
        // shift+S -> play from start timestamp
        if(charCode == 83) {
            if( e.shiftKey ) {
                video.currentTime = to_sec(document.getElementById("timer_start").value);
            } else {
                document.getElementById("timer_start").value = to_ts( video.currentTime );
            };
        };
        // D
        if(charCode == 68) { stepff('timer_start',+1 * (e.shiftKey ? 0.1 : 1 ))};
        // A
        if(charCode == 65) { stepff('timer_start',-1 * (e.shiftKey ? 0.1 : 1 ))};

        // X -> use as end timestamp
        // shift+X -> play to end timestamp
        if(charCode == 88) {
            if( e.shiftKey ) {
                video.pause();
                playUntil = to_sec( document.getElementById("timer_stop").value );
                video.currentTime = playUntil -3;
                video.play();
            } else {
                document.getElementById("timer_stop").value = to_ts( video.currentTime );
            };
        };
        // C -> move end timestamp
        if(charCode == 67) { stepff('timer_stop',+1 * (e.shiftKey ? 0.1 : 1 ))};
        // Y/Z -> move end timestamp
        if(charCode == 89 || charCode == 90) { stepff('timer_stop',-1 * (e.shiftKey ? 0.1 : 1 ))};

        // shift+G -> jump to end of video
        if(charCode == 71) {
            video.currentTime = video.duration;
        };
    });
    document.getElementById("timer").focus();
};

function stepff(control,amount) {
    var ts = 0;
    if( control ) {
        var c = document.getElementById(control);
        ts = to_sec( c.value ) + amount;
        c.value = to_ts( ts );
    } else {
        ts = video.currentTime + amount;
    };
    video.currentTime = ts;
};

function to_sec(ts) {
    var res = 0;
    ts = ts.replace(/(?:^|:)(\d+)/g, function(m,v) {
        res = res * 60 + parseInt( v,10 );
        return "";
    });
    ts = ts.replace(/^\.(\d+)/, function(m,v) {
        res = res + parseInt( "0."+v,10 );
        return "";
    });
    if( ts ) {
        alert( "Invalid timestamp " + ts );
    };
    return res;
};

function to_ts(sec) {
    var dt = new Date(sec*1000);
    var hr = dt.getHours()-1;
    var m = "0" + dt.getMinutes();
    var s = "0" + dt.getSeconds();
    var ms = "0000" + (sec *1000 % 1000);
    return hr+ ':' + m.substr(-2) + ':' + s.substr(-2) + "." + ms.substr(-4);
};
</script>
</head>
<body id="mybody" onload="ready()">
<a id="lnkIndex" href="/">Back</a><br />
<video id="myvideo" preload="auto" controls >
    <source src="/video/<%= $file %>" type='video/mp4' />
</video>

<form method="POST" enctype="multipart/form-data" id="thatform" accept-charset="utf-8">
<div id="controls">
    <div id="timer">00:00:00.0000</div>
    <button onclick="javascript:stepff('timer_start', -0.1); return false">&lt;</button>
    <input type="text" id="timer_start" name="start" value="<%= $start %>" />
    <button onclick="javascript:stepff('timer_start', +0.1); return false">&gt;</button>
    </div><div>
    <button onclick="javascript:stepff('timer_stop', -0.1); return false">&lt;</button>
    <input type="text" id="timer_stop" name="stop" value="<%= $stop %>" />
    <button onclick="javascript:stepff('timer_stop', +0.1); return false">&gt;</button>
    </div>
</div>
<label for="title">Title</label><input type="text" name="title" value="<%= $metadata->{title} %>" /><br />
<label for="artist">Artist</label><input type="text" name="artist" value="<%= $metadata->{artist} %>" /><br />
<label for="show">Show</label><input type="text" name="show" value="<%= $metadata->{show} %>" /><br />
<label for="url">URL</label><input type="text" name="url" value="<%= $metadata->{url} %>" /><br />
<label for="language">Language</label><input type="text" name="language" value="<%= $metadata->{language} %>" /><br />
<button type="submit" id="btnSave">Save</button>
</form>

<ul>
<li><kbd>q</kbd> - move start point one second earlier</li>
<li><kbd>shift+q</kbd> - move start point 0.1 second earlier</li>
<li><kbd>e</kbd> - move start point one second later</li>
<li><kbd>shift+e</kbd> - move start point 0.1 second later</li>
<li><kbd>s</kbd> - set video start point</li>
<li><kbd>shift+S</kbd> - play video from start point</li>
<li><kbd>d</kbd> - step video play position 1 second earlier</li>
<li><kbd>a</kbd> - step video play position 1 second later</li>
<li><kbd>x</kbd> - use current position as end position</li>
<li><kbd>y/z</kbd> - move end position earlier</li>
<li><kbd>c</kbd> - move end position later</li>
<li><kbd>shift+g</kbd> - jump to end of video</li>
<li><kbd>f</kbd> - save current cutmarks</li>
<li><kbd>i</kbd> - go back to the index page</li>
</ul>
</body>
</html>
