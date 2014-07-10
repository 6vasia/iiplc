# Copyright (c) 2014, Vasiliy Vylegzhanin <v.gadfly@gmail.com>
# Copyright (c) 2014, Difrex <difrex.punk@gmail.com>
# Some rights reserved.
package II::Enc;

use II::DB;
use MIME::Base64;
use Encode qw(encode_utf8);

sub new {
    my $class = shift;

    my $db = II::DB->new();

    my $self = {
        _config => shift,
        _data   => shift,
        _db     => $db,
    };

    bless $self, $class;
    return $self;
}

sub decrypt {
    my ( $self, $base64 ) = @_;
    return decode_base64($base64);
}

sub encode {
    my ($self) = @_;
    my $config = $self->{_config};
    my $data   = $self->{_data};
    my $db     = $self->{_db};
    my $hash   = II::Enc->new_hash();

    # Make base64 message
    my $message = $data->{echo} . "\n";
    $message .= $data->{to} . "\n";
    $message .= $data->{subj} . "\n\n";
    $message .= '@repto:' . $data->{hash} . "\n" if defined( $data->{hash} );
    $message .= $data->{post};

    my $encoded = encode_base64(encode_utf8($message));
    $encoded =~ s/\//_/g;
    $encoded =~ s/\+/-/g;

    $db->write_out(
        echo    => $data->{echo},
        from    => $data->{from},
        to      => $data->{to},
        subj    => $data->{subj},
        post    => $data->{post},
        base64  => $encoded,
        sent    => 0,
    );
    return 0;
}

sub new_hash {
    my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
    my $string;
    $string .= $chars[ rand @chars ] for 1 .. 21;

    return $string;
}

1;
