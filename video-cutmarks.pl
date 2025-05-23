#!/usr/bin/perl
use strict;
use 5.020;
use feature 'signatures', 'postderef';
no warnings 'experimental::signatures';

use Mojolicious::Lite;
use Mojolicious::Static;
use Mojo::JSON 'encode_json';
use Mojo::Util 'url_escape', 'url_unescape', 'decode', 'encode';
use Cwd;
use YAML 'LoadFile', 'Dump';
use File::Basename;
use POSIX qw(strftime);

plugin AutoReload => {};

my $config;
if( ! $ENV{CONFIG}) {
    die "No CONFIG= given!";
};

open my $fh, '<', $ENV{CONFIG}
    or die "Couldn't read config file '$ENV{CONFIG}'";
my %config = map { /^\s*([^#].*?)=(.*)/ ? ($1 => $2) : () } <$fh>;

unshift app->static->paths->@*, $config{VIDEO};

app->types->type( MP4 => 'video/mp4' );
app->types->type( mkv => 'video/webm' );

sub video_file {
    my ($fn) = @_;
    return $fn;
}

sub yaml_file {
    my ($fn) = @_;
    return $config{VIDEO} . '/' . $fn;
}

# We want a sorted list of files so prev/next work
sub input_files {
    map { s/\.(mkv|MP4)$//i;
          my $f = basename(decode('UTF-8',$_));
          { file => encode_name($f),
            name => decode('UTF-8', basename($_)),
            %{ fetch_config( basename($_) ) },
        }
    }
    sort { $a cmp $b }
    glob $config{VIDEO} . '/*.{MP4,mkv}'
}

get '/' => sub {
    my( $c ) = @_;
    my $files = [ input_files() ];
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

helper 'encode_json' => sub( $c, $info ) {
    return encode_json($info)
};

get '/video/<*name>.<ext>' => sub {
    my( $c ) = @_;
    my $ext = $c->param('ext');
    return unless $ext =~ /^(MP4|mkv)$/i;
    my $base = decode_name($c->param('name'));
    $base = decode('UTF-8', $base);
    my $file = video_file( $base . ".$ext" );
    $c->reply->static( $file );
};

sub fetch_config {
    my( $base) = (@_);
    my $info = yaml_file($base. '.yml');

    if( ! -f $info ) {
        # Should we make up random content here?!
        # We should shell out to the metadata generator instead!
        $info = {
            cutmarks => [],
            metadata => {
                artist    => "",
                language => "deu",
                show => $config{ SHOW },
                title => "",
                url => strftime( 'https://act.yapc.eu/gpw%Y/talk/', localtime()),
            },
        };

    } else {
        $info = LoadFile( $info );
    }
    return $info
}

sub update_file( $filename, $new_content ) {
    my $content;
    if( -f $filename ) {
        open my $fh, '<', $filename
            or die "Couldn't read '$filename': $!";
        binmode $fh, ':utf8';
        local $/;
        $content = <$fh>;
    };

    if( $content ne $new_content ) {
        if( open my $fh, '>', $filename ) {
            binmode $fh, ':utf8';
            print $fh $new_content;
        } else {
            warn "Couldn't (re)write '$filename': $!";
        };
    };
}

get '/cut/<*name>' => sub {
    my( $c ) = @_;
    my $base = encode('UTF-8', decode_name($c->param('name')));
    my $file = $config{VIDEO} .'/'. $base . '.';
    (my $ext) = grep { -f $file . $_ } (qw(MP4 mkv));
    my $mark = $c->param('cutmark') // 0;

    if(! $ext) {
        warn "File '$file*' not found";
        return;
    };

    my @input_files = input_files();
    my $curr = 0;
    for my $f ( @input_files ) {
        if( $f->{file} eq $base ) {
            last
        }
        $curr++;
    };

    $file .= $ext;

    my $info = fetch_config( $base );
    $c->stash( file => basename($file),
               $curr < $#input_files ? ("next" => $input_files[$curr+1]) : ("next" => undef),
               $curr > 0             ? (prev   => $input_files[$curr-1]) : (prev => undef),
               cutmark => $mark,
               %$info
            );
    $c->render( template => 'cutname' );
};

post '/cut/<*name>' => sub {
    my( $c ) = @_;
    # This should be based on the names in the .yml instead of guessing the name
    # from the central base, but whatever
    my $file = $config{VIDEO} .'/'. decode_name($c->param('name')) . ".";
    my $filename_unicode = $file;
    $file = encode('UTF-8', $file);
    (my $ext) = grep { -f $file . $_ } (qw(MP4 mkv));
    return unless $ext;
    $filename_unicode .= $ext;
    $file .= $ext;
    my $yml = yaml_file(decode_name($c->param('name')) . '.yml');
    # This should be corrected, by allowing more cutmarks in the UI itself too

    # load the old cutmarks
    my $old = fetch_config(decode_name($c->param('name')));
    # Patch in the current cutmarks according to param('cutmark')
    my $cutmarks = $old->{cutmarks};
    my $cutmark = $c->param('cutmark')+0;

    my $action = $c->param('action');
    if( $action eq 'edit') {
        $cutmarks->[ $cutmark ] = {
            inpoint  => $c->param('start'),
            outpoint => $c->param('stop'),
            file     => $filename_unicode,
        };

    } else {
        # How do we handle deletions?!
        die "Splicing on cutmarks is not yet implemented";
    };

    my $info = {
        cutmarks => $cutmarks,
        metadata => {
            title => $c->param('title'),
            artist => $c->param('artist'),
            show   => $c->param('show'),
            language => $c->param('language'),
            url  => $c->param('url'),
        },
    };

    # Only overwrite the file if we have new/different content, since we
    # now always "save" in the UI
    update_file( $yml, Dump( $info ));
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
<li><a href="/cut/<%= $file->{file} %>"><%=$file->{name}%></a> - <%= $file->{metadata}->{title} %> - <%= $file->{metadata}->{artist} %></li>
%}
</ol>
</body>
</html>

@@app.css
#last_keycode { float: right; }
video { width: 100%; }

@@cutname.html.ep
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<link rel="stylesheet"  type="text/css" href="/app.css" />
<script>
"use strict";
let video;

// No - we should load these via a JSON API instead
let cutmarks = <%== encode_json( $cutmarks ) %>;

let midiInput;
let midiOutput;
let playUntil = undefined;

function currentTrack() {
    return parseInt( document.getElementById("cutmark").value, 10 );
}

function saveForm(e) {
    let http = new XMLHttpRequest();
    let url = window.location;
    let params = [];

    let inputs = document.querySelectorAll("input[value]");
    for( let el = 0; el < inputs.length; el++ ) {
        params.push(encodeURIComponent(inputs[el].name) + '=' + encodeURIComponent(inputs[el].value))
    };
    let payload = params.join('&').replace(/%20/g, '+');

    http.open('POST', url, true);
    http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

    http.onreadystatechange = function() {
        if(http.readyState == 4 && http.status == 200) {
            // everything went OK
        }
    }
    http.send(payload);

    if( e.preventDefault ) {
        e.preventDefault();
    }
    return false;
}

let commands = {
    nextEntry: function() {
        saveForm({});
        let page = document.getElementById("lnkNext");
        window.location.assign( page.href );
    },
    prevEntry: function() {
        saveForm({});
        let page = document.getElementById("lnkPrev");
        window.location.assign( page.href );
    },
    backToIndex: function() {
        saveForm({});
        let indexPage = document.getElementById("lnkIndex");
        window.location.assign( indexPage.href );
    },
    playPause: function() {
        if (video.paused) {
            video.play()
        } else {
            video.pause()
        }
    },
    jumpToStart: function() {
        video.currentTime = 0;
    },
    jumpToEnd: function() {
        video.currentTime = video.duration;
    },
    setStartCue: function() {
        document.getElementById("timer_start").value = to_ts( video.currentTime );
    },
    jumpToStartCue: function() {
        video.currentTime = to_sec(document.getElementById("timer_start").value);
    },
    eraseStartCue: function() {
        document.getElementById("timer_start").value = "";
    },
    setEndCue: function() {
        document.getElementById("timer_stop").value = to_ts( video.currentTime );
    },
    jumpToEndCue: function() {
        video.currentTime = to_sec(document.getElementById("timer_stop").value);
    },
    playToEndCue: function() {
        video.pause();
        playUntil = { track: currentTrack(), ts: to_sec( document.getElementById("timer_stop").value )};
        video.currentTime = playUntil.ts -3;
        video.play();
    },
    eraseEndCue: function() {
        document.getElementById("timer_stop").value = "";
    },

    nextCutmark: function() {
        // Save current stuff
        saveForm({});

        // Now check if we can move one cutmark further:
        if( currentTrack() < cutmarks.length-1 ) {
            // We can move one further, so reload the page with the updated current track:
            let q = new URLSearchParams(window.location.search);
            q.set("cutmark", currentTrack()+1);
            window.location.search = q.toString();
        } else {
            console.log("At end of cutmarks");
        }
    },
    prevCutmark: function() {
        // Save current stuff
        saveForm({});

        // Now check if we can move one cutmark further:
        if( currentTrack() > 0 ) {
            // We can move one previous, so reload the page with the updated current track:
            let q = new URLSearchParams(window.location.search);
            q.set("cutmark", currentTrack()-1);
            window.location.search = q.toString();
        } else {
            console.log("At start of cutmarks");
        }
    },

    saveCurrentState: function() {
        saveForm({});
    },
};

function doCommand(cmd) {
    let cb = commands[cmd];
    if( cb ) {
        //console.log(cmd);
        cb();
    } else {
        console.log(`Unknown command '${cmd}'`);
    }
}

// 16-bit input map
// high byte is shift
let KeyboardMap = {
    // F -> save the current state
    0x0046 : (e) => { doCommand('saveCurrentState' ) },
    // shift+G -> jump to end of file
    0x0147 : (e) => { doCommand('jumpToEnd'); },
    // I -> go back to index page
    0x0049 : (e) => { doCommand('backToIndex' ) },
    // M -> next video
    0x004D : (e) => { doCommand('nextEntry' ) },
    // N -> prev video
    0x004E : (e) => { doCommand('prevEntry' ) },
    // Spacebar
    0x0020 : (e) => { doCommand('playPause' )},
    // S -> Use as start timestamp
    0x0053 : (e) => { doCommand('setStartCue'); },
    // shift+S -> play from start timestamp
    0x0153 : (e) => { doCommand('jumpToStartCue'); },
    // X -> Use as end timestamp
    0x0058 : (e) => { doCommand('setEndCue'); },
    // shift+X -> play until end timestamp
    0x0158 : (e) => { doCommand('playToEndCue'); },
}

function onKeyboardInput(e) {
    e = e || window.event;
    if( e.target.tagName == "INPUT" ) return;
    let charCode = e.which || e.keyCode;

    let entry = e.shiftKey * 256 + charCode;
    document.getElementById("last_keycode").innerHTML = entry.toString(16);
    let cb = KeyboardMap[ entry ];
    if(cb) {
        cb(e);
        return;
    }
}

let MidiShift; // Shift key held
let MidiKeystate = {};
let MidiMap = {
    // Shift key
    //0x9e00 : (d) => { MidiShift = true },
    //0x8e00 : (d) => { MidiShift = false },

    // Left play/pause key
    0x9000 : (d) => { doCommand('playPause') },
    0x9005 : (d) => { doCommand('jumpToStart') },
    0x9428 : (d) => { doCommand('jumpToStart') },
    0x9429 : (d) => { doCommand('jumpToEnd') },
    //0x9006 : (d) => { doCommand('touchHold') },
    // Mid track selector for track nav
    0x9414 : (d) => {
                // Set in cue point if we don't have one yet
                doCommand('setStartCue');
                midiOutput.send([0x94,0x14,0x7f]); // Light up the pad
                midiOutput.send([0x94,0x1C,0x7f]); // (also the shifted button)
                // Should we play if held?!
                // Should we jump to cue point if we already have one
            },
    0x9415 : (d) => {
                // Set in cue point if we don't have one yet
                doCommand('setEndCue');
                midiOutput.send([0x94,0x15,0x7f]); // Light up the pad
                midiOutput.send([0x94,0x1D,0x7f]); // (also the shifted button)
                // Should we play if held?!
                // Should we jump to cue point if we already have one
            },
    0x941C : (d) => {
                doCommand('eraseStartCue');
                midiOutput.send([0x94,0x14,0x00]); // Dim the pad
                midiOutput.send([0x94,0x1C,0x00]); // Dim the shifted
            },
    0x9418 : (d) => {
                // Set in cue point if we don't have one yet??
                doCommand('jumpToStartCue');
                // Should we play if held?!
            },
    0x9419 : (d) => {
                // Set in cue point if we don't have one yet??
                doCommand('playToEndCue');
                // Should we play if held?!
            },
    0x9E06 : (d) => { doCommand('backToIndex') }, // actually we should have the track as a selectable pane ...
    // left jog wheel for nav
    0xB006 : (d) => {
                // XXX This should be a doCommand!
                let direction = d[2] > 0x7f ? -1 : 1;
                let scale = {
                    0x7e : -0.2,
                    0x7f : -0.1,
                    0x01 :  0.1,
                    0x02 :  0.2,
                };
                let magnitude = scale[ d[2]];
                if( ! magnitude ) {
                    magnitude = 1;
                };
                stepff('', direction * magnitude );
            },
    0xBE00 : (d) => {
                // XXX This should be a doCommand!
                let direction = d[2] > 0x40 ? -1 : 1;
                if( direction < 0 ) {
                    doCommand('prevEntry');
                } else {
                    doCommand('nextEntry');
                }
            },
    0x900d : (d) => { doCommand('nextCutmark') },
    0x900f : (d) => { doCommand('prevCutmark') },
};

function onMidiInput(e) {
    // e.data has the MIDI message
    if( e.data[0] != 0xf0 ) { // ignore sysex messages ?!
        let keycode = event.data.reduce(function(s, x) {
          return s + " " + x.toString(16).padStart(2, "0");
        }, "").slice(1);
        document.getElementById("last_keycode").innerHTML = keycode;
        let key_id = e.data[0] * 256 + e.data[1];
        let cb = MidiMap[ e.data[0] * 256 + e.data[1] ];

        if( key_id & 0xF000 == 0x9000 ) {
            MidiKeystate[key_id] = true;
        } else {
            MidiKeystate[key_id | 0x9000] = false;
        }

        if(cb) {
            cb(e.data);
        }

    }
}

async function setupMidiInput() {
    let access;
    try {
        access = await navigator.requestMIDIAccess({sysex: true});
    } catch {
        // No MIDI for you
        return null;
    }

    document.getElementById('navigation-midi').style.display = 'block';
    document.getElementById('navigation-keyboard').style.display = 'none';

    // access.statechange is fired when a device is connected/disconnnected
    // Hardcoded to the device(s) of interest:
    access.inputs.forEach( port => { if( port.name.match(/\bReloop\b/)) { midiInput = port } } );
    if( ! midiInput ) {
        // Take the first device, if any
        midiInput = access.inputs[0];
    }

    if( midiInput ) {
        midiInput.addEventListener( 'midimessage', onMidiInput );
    }

    access.outputs.forEach( port => { if( port.name.match(/\bReloop\b/)) { midiOutput = port } } );
    if( ! midiOutput ) {
        // Take the first device, if any
        midiOutput = access.outputs[0];
    }

    if( midiInput ) {
        midiInput.addEventListener( 'midimessage', onMidiInput );
    }

}

function ready() {
    video = document.getElementById("myvideo");
    let seeking = false;
    video.addEventListener('timeupdate', async function() {
        document.getElementById("timer").innerHTML = to_ts( video.currentTime );
        let curr = currentTrack();
        if( playUntil ) {
            if( ! seeking ) {
                if( curr == playUntil.track-1 || curr == cutmarks.length) {
                    await video.pause();

                    // Test the transition
                    if( curr < cutmarks.length -1 ) {
                        seeking = true;
                        video.currentTime = to_sec(cutmarks[ curr+1 ].inpoint);
                        // How can we wait here so we know when to play again?!
                        await video.play();
                        seeking = false;
                    } else if( curr == cut ) {
                    } else {
                        // Remain stopped
                        playUntil = undefined;
                    }
                }
            }
        };
    });
    let btnSave = document.getElementById("btnSave");
    btnSave.addEventListener('click', saveForm );

    document.addEventListener('keydown', onKeyboardInput);
    document.getElementById("timer").focus();

    setupMidiInput().then(() => {
        if( midiOutput ) {
            for (let pad of [0x14,0x15,0x16,0x17,
                         0x1C,0x1D,0x1E,0x1F,
                ]) {
                // Switch off all pads
                midiOutput.send([0x94, pad, 0x00]);
            }
        }
        console.log("MIDI setup done");
    });

};

function stepff(control,amount) {
    let ts = 0;
    if( control ) {
        let c = document.getElementById(control);
        ts = to_sec( c.value ) + amount;
        c.value = to_ts( ts );
    } else {
        ts = video.currentTime + amount;
    };
    video.currentTime = ts;
};

function to_sec(ts) {
    let res = 0;
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
    let dt = new Date(sec*1000);
    let hr = dt.getHours()-1;
    let m = "0" + dt.getMinutes();
    let s = "0" + dt.getSeconds();
    let ms = "0000" + (sec *1000 % 1000);
    return hr+ ':' + m.substr(-2) + ':' + s.substr(-2) + "." + ms.substr(-4);
};
</script>
</head>
<body id="mybody" onload="javascript:ready()">
<nav id="Navigation">
   <a id="lnkIndex" href="/">Back</a>
% if( $prev ) {
 - <a id="lnkPrev" href="<%= $prev->{file} %>">Prev</a>
% }
% if( $next ) {
 - <a id="lnkNext" href="<%= $next->{file} %>">Next</a>
% }
</nav>
<video id="myvideo" preload="auto" controls >
    <source src="/video/<%= $file %>" type='video/mp4' />
</video>
<span id="last_keycode">(no keypress)</span>
<form method="POST" enctype="multipart/form-data" id="thatform" accept-charset="utf-8">
<div id="controls">
    <div id="timer">00:00:00.0000</div>
    <table>
% for my $mark (0..$#$cutmarks) {
    <tr>
%     if( $mark == $cutmark ) {
    <input type="hidden" id="cutmark" name="cutmark" value="<%= $cutmark %>" />
    <input type="hidden" id="cutmark" name="action" value="edit" />
    <td>
        <button onclick="javascript:stepff('timer_start', -0.1); return false">&lt;</button>
    </td><td>
        <input type="text" id="timer_start" name="start" value="<%= $cutmarks->[$mark]->{inpoint} %>" />
    </td><td>
        <button onclick="javascript:stepff('timer_start', +0.1); return false">&gt;</button>
    </td>
    <td>
        <button onclick="javascript:stepff('timer_stop', -0.1); return false">&lt;</button>
    </td><td>
        <input type="text" id="timer_stop" name="stop" value="<%= $cutmarks->[$mark]->{outpoint} %>" />
    </td><td>
        <button onclick="javascript:stepff('timer_stop', +0.1); return false">&gt;</button>
    </td>
%     } else {
    <td>
    </td><td>
    <a href="<%= url_with->query({ cutmark => $mark }) %>">
        <%= $cutmarks->[$mark]->{inpoint} %>
    </a>
    </td><td>
    </td>
    <td>
    </td><td>
        <%= $cutmarks->[$mark]->{outpoint} %>
    </td><td>
    </td>
%     }
    </tr>
% }
    </table>
</div>
<label for="title">Title</label><input type="text" name="title" value="<%= $metadata->{title} %>" /><br />
<label for="artist">Artist</label><input type="text" name="artist" value="<%= $metadata->{artist} %>" /><br />
<label for="show">Show</label><input type="text" name="show" value="<%= $metadata->{show} %>" /><br />
<label for="url">URL</label><input type="text" name="url" value="<%= $metadata->{url} %>" /><br />
<label for="language">Language</label><input type="text" name="language" value="<%= $metadata->{language} %>" /><br />
<button type="submit" id="btnSave">Save</button>
</form>

<ul id="navigation-keyboard">
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
<ul id="navigation-midi">
<li>play/pause - play/pause</li>
<li>left jog - navigate</li>
<li>parameter 1 - jump to start/end</li>
<li>pad 1 - set inpoint</li>
<li>shift+pad 1 - clear inpoint</li>
<li>shift+pad 2 - clear outpoint</li>
</ul>
</body>
</html>
