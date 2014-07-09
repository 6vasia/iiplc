package II::Send;

use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use II::DB;
use Data::Dumper;

sub new {
    my $class = shift;

    my $db   = II::DB->new();
    my $self = {
        _config => shift,
        _echo   => shift,
        _base64 => shift,
        _db     => $db,
    };

    bless $self, $class;
    return $self;
}

sub send {
    my ( $self, $hash ) = @_;
    my $config = $self->{_config};
    my $echo   = $self->{_echo};
    my $base64 = $self->{_base64};
    my $db     = $self->{_db};

    # Push message to server
    my $host = $config->{host};
    my $auth = $config->{key};
    $host .= "u/point";
    my $ua = LWP::UserAgent->new();
    my $response
        = $ua->post( $host, { 'pauth' => $auth, 'tmsg' => $base64 } );

    if ( $response->{_rc} == 200 ) {
        $db->update_out($hash);
    }
}

sub push {
    my ($self, $host) = @_;
    my $db = $self->{_db};
    
    my @outmesg = $db->host_out;
    for my $out (@outmesg) {
        my $auth = $db->user($out->{from})->{auth};
        my $ua = LWP::UserAgent->new;
        $ua->agent("iiplc/0.1rc1");
        print STDERR Dumper $out;
        my $response
            = $ua->post( $host.'u/point', { 'pauth' => $auth, 'tmsg' => $out->{base64} } );

        if ( $response->{_rc} == 200 ) {
            $db->update_out($out->{id});
        } else {
            print STDERR "push failed for msg $out->{id}\n",$response->content,"\n";
        }
    }
}

sub push_all {
    my $self = shift;
    my @hosts = $self->{_db}->hosts;
    for my $h (@hosts) {
        $self->{_db}->open($h);
        $self->push($h);
    }
}
1;
