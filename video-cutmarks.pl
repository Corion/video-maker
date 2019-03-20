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
    my $files = [ map { s/\.joined.MP4//i; $_ } glob '*.joined.MP4' ];
    $c->stash( files => $files);
    $c->render( template => 'index' );
};

get '/video/<name>.joined.MP4' => sub {
    my( $c ) = @_;
    my $file = $c->param('name') . ".joined.MP4";
    $c->reply->static( $file );
};

get '/cut/<name>' => sub {
    my( $c ) = @_;
    my $file = $c->param('name') . ".joined.MP4";
    my $info = $c->param('name') . '.yml';
    $info = LoadFile( $info );
    $c->stash( file => $file, %$info  );
    $c->render( template => 'cut' );
};

post '/cut/<name>' => sub {
    my( $c ) = @_;
    my $file = $c->param('name') . ".joined.MP4";
    my $yml = $c->param('name') . '.yml';
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
    $c->redirect_to($c->url_for('/cut/' . $c->param('name')));
};

app->start;

__DATA__
@@index.html.ep
<html>
<body>
<ol>
%for my $file (@$files) {
<li><a href="/cut/<%= $file %>"><%=$file%></a></li>
%}
</ol>
</body>
</html>

@@cut.html.ep
<html >
<head>
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
        // E -> step back a second
        if(charCode == 69) { stepff('',+1 * (e.shiftKey ? 0.1 : 1 ))};

        // S -> Use as start timestamp, switch to end timestamp
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

        // Y/Z -> Use as stop timestamp, switch to end timestamp
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
        if(charCode == 67) { stepff('timer_stop',+1 * (e.shiftKey ? 0.1 : 1 ))};
        if(charCode == 89 || charCode == 90) { stepff('timer_stop',-1 * (e.shiftKey ? 0.1 : 1 ))};

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
    var ms = "0000" + (sec % 1);
    return hr+ ':' + m.substr(-2) + ':' + s.substr(-2) + "." + ms.substr(-4);
};
</script>
</head>
<body id="mybody" onload="ready()">
<a id="lnkIndex" href="/">Back</a><br />
<video id="myvideo" preload="auto" controls >
    <source src="/video/<%= $file %>" type='video/mp4' />
</video>

<form method="POST" enctype="multipart/form-data" id="thatform">
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
<label for="artist">Author</label><input type="text" name="artist" value="<%= $metadata->{artist} %>" /><br />
<label for="show">Show</label><input type="text" name="show" value="<%= $metadata->{show} %>" /><br />
<label for="url">URL</label><input type="text" name="url" value="<%= $metadata->{url} %>" /><br />
<label for="language">Language</label><input type="text" name="language" value="<%= $metadata->{language} %>" /><br />
<button type="submit" id="btnSave">Save</button>
</form>

</body>
</html>
