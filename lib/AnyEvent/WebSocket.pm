
=head1 NAME

AnyEvent::WebSocket - AnyEvent implementation of Web Sockets

=head1 SYNOPSIS

    # AnyEvent::WebSocket expects to be given
    # a socket where the client has already
    # sent its handshake, and it will generate
    # the response handshake.
    my $ws = AnyEvent::WebSocket->new(
        socket => $sock,
        key1 => $key1,
        key2 => $key2,
        body => $body,
        origin => $origin,
        location => $uri,
    );

=head1 DESCRIPTION

AnyEvent::WebSocket is an implementation of the Web Sockets
protocol (specifically draft-hixie-thewebsocketprotocol-76)
in terms of AnyEvent.

It is designed to take over a socket from an AnyEvent-based
HTTP server once that server has detected the WebSocket
upgrade request headers and extracted the necessary data
from the handshake. This module will then do all of the work
to send back the server's half of the handshake and then
manage the ongoing WebSocket connection.

=head1 USAGE WITH A PSGI APPLICATION

L<PSGI> is a specification for an interface between a web
server and a web application written in Perl. The recommended
way to use this module is from a PSGI app running inside L<Twiggy>,
an AnyEvent-based PSGI container. An example of this usage is
included in the file F<eg/psgihandoff.psgi> in this module's
distribution.

=cut

package AnyEvent::WebSocket;

use strict;
use warnings;
use AnyEvent;
use AnyEvent::Handle;
use Digest::MD5 qw(md5);
use Carp qw(croak);
use base qw(Class::Accessor);

__PACKAGE__->mk_accessors(qw(socket key1 key2 body origin location on_error on_close on_frame on_open protocol));

sub new {
    my ($class, %param) = @_;

    my $self = bless {}, $class;

    foreach my $k (qw(socket key1 key2 body origin location)) {
        $self->{$k} = delete $param{$k} or croak "'$k' parameter is required";
    }
    foreach my $k (qw(on_error on_close on_frame on_open protocol)) {
        $self->{$k} = delete $param{$k};
    }

    croak "Unrecognized arguments: ".join(', ', keys %param) if %param;

    # Default error handler is to die, to aid debugging.
    $self->{on_error} ||= sub { die "AnyEvent::WebSocket unhandled error: ".shift };
    $self->{on_close} ||= sub { };
    $self->{on_frame} ||= sub { };
    $self->{on_open} ||= sub { };

    $self->{h} = AnyEvent::Handle->new( fh => $self->{socket} );

    $self->{h}->on_error(sub { $self->{on_error}->($_[2]) });
    $self->{h}->on_eof(sub { $self->{on_close}->() });

    return $self;
}

sub begin {
    my ($self) = @_;

    my $process_key = sub {
        my ($key) = @_;
        my $digits = join('', $key =~ m/\d/g);
        my $spaces = scalar @{[$key =~ m/ /g]};
        return $digits / $spaces;
    };

    my $base_string = pack("NN", $process_key->($self->{key1}), $process_key->($self->{key2})) . $self->{body};
    my $sig = md5($base_string);
    my $protocol = $self->{protocol};
    my $handshake = join "\015\012", (
        "HTTP/1.1 101 Web Socket Protocol Handshake",
        "Upgrade: WebSocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Origin: ".$self->origin,
        "Sec-WebSocket-Location: ".$self->location,
        ($protocol ? "Sec-WebSocket-Protocol: $protocol" : ()),
        '',
        ''
    );

    warn $handshake;
    warn "Signature is ".length($sig)." bytes long\n";

    $self->{h}->push_write($handshake);
    $self->{h}->push_write($sig);

    $self->{on_open}->($self);

    $self->{h}->on_read(sub { $self->_handle_frame() });

    $self->_wait_for_frame();
}

sub send_frame {
    my ($self, $payload) = @_;

    $self->{h}->push_write("\x00");
    $self->{h}->push_write($payload);
    $self->{h}->push_write("\xFF");
}

sub _handle_frame {
    my ($self) = @_;

    my $h = $self->{h};
    $h->unshift_read(chunk => 1, sub {
        my $type_byte = $_[1];

        my ($type) = unpack("C", $type_byte);

        if ($type == 0) {
            warn "Got a type 0 frame. waiting for body...";
            $h->unshift_read(line => "\xFF", sub {
                my $string = $_[1];
                warn "Got frame containing text $string";
                $self->{on_frame}->($string);
            });
        }
        else {
            die "Frame type $type is not yet implemented";
        }
    });
}

1;

