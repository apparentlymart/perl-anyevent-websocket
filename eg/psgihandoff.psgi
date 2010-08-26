
use lib "../lib";
use Plack::Request;
use Plack::Response;
use Data::Dumper;
use AnyEvent::WebSocket;

my @page = <DATA>;

sub app {
    my ($env) = @_;

    warn "Request for $env->{PATH_INFO}";

    if ($env->{PATH_INFO} eq '/page') {
        return [ 200, [ "Content-Type" => 'text/html', ], \@page ];
    }

    # Fail hard if we're not running in a suitable
    # PSGI container.
    unless ($env->{'psgix.io'} && $env->{'psgi.nonblocking'} && $env->{'psgi.streaming'} && $env->{'psgix.input.buffered'}) {
        return [ 500, [ "Content-Type" => 'text/html', ], [ "This example only works inside an AnyEvent-powered non-blocking PSGI container which has a buffered input stream, such as Twiggy" ] ];
    }

    my $req = Plack::Request->new($env);

    if ($req->header('Upgrade') eq 'WebSocket') {
        # Hand the socket for this request over to
        # websocket code.
        warn "This is a WebSocket handshake";

        my $sock = $env->{'psgix.io'} || die "No socket";
        warn "Reading from socket $sock";

        my $origin = $req->header('Origin');
        my $key1 = $req->header('Sec-WebSocket-Key1');
        my $key2 = $req->header('Sec-WebSocket-Key2');
        my $body;

        # WebSocket handshake doesn't have Content-Length, so
        # Twiggy leaves the body in the socket buffer for us to read.
        warn "About to read body";
        my $bytes_read = read($sock, $body, 8);
        die "Failed to read body: $!" unless defined($bytes_read);
        warn "Read body and got $bytes_read bytes";
        if ($bytes_read != 8) {
            warn "Invalid handshake: missing 8-byte verifier";
            return [ 400, [ "Content-Type" => 'text/html', ], [ "Handshake is missing the 8-byte verifier" ] ];
        }

        my $uri = $req->uri->canonical;
        $uri =~ s!^http!ws!;

        my $ws = AnyEvent::WebSocket->new(
            socket => $sock,
            key1 => $key1,
            key2 => $key2,
            body => $body,
            origin => $origin,
            location => $uri,
        );
        warn Data::Dumper::Dumper($ws);
        warn "Returning a CODE ref";

        $ws->on_frame(sub {
            my $content = shift;
            warn "Got a frame containing $content! Echoing it back...";
            $ws->send_frame("You said $content");
        });

        return sub {
            warn "In our CODE ref";
            $ws->begin();
        };
    }
    else {
        my $res = Plack::Response->new(200);
        $res->body("Environment is ".Data::Dumper::Dumper($env));

        return $res->finalize();
    }

}

# Return a reference to app, per the PSGI spec.
\&app;

__DATA__

<html>

<head>

<script src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"></script>
<script>

$(document).ready(function(){

var ws;

if ("WebSocket" in window) {
debug("Horray you have web sockets. Trying to connect...");
ws = new WebSocket("ws://127.0.0.1:8080/echo");

ws.onopen = function() {
// Web Socket is connected. You can send data by send() method.
debug("connected...");
ws.send("hello from the browser");
ws.send("more from browser");
};

run = function() {
var val=$("#i1").val(); // read the entry
$("#i1").val("");       // and clear it
ws.send(val);           // tell erlang
return true;            // must do this
};

ws.onmessage = function (evt)
{
//alert(evt.data);
var data = evt.data;
debug("Recieved message containing "+data);
};

ws.onerror = function() {
    debug("Error!");
}

ws.onclose = function()
{
debug(" socket closed");
};
} else {
alert("You have no web sockets");
};

function debug(str){
$("#debug").append("<p>" +  str);
};

});
</script>

</head>

<body>

<h1>Interaction experiment</h1>

<h2>Debug</h2>
<div id="debug"></div>

<fieldset>
<legend>Clock</legend>
<div id="clock">I am a clock</div>
</fieldset>

</body>

</html>
