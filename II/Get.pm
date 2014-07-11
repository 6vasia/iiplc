# Copyright (c) 2014, Vasiliy Vylegzhanin <v.gadfly@gmail.com>
# Copyright (c) 2014, Difrex <difrex.punk@gmail.com>
# Some rights reserved.

package II::Get;
use LWP::UserAgent;
use HTTP::Request;
use Encode;

use II::DB;
use II::Enc;

use Data::Dumper;

sub new {
    my $class = shift;

    my $ua = LWP::UserAgent->new();
    $ua->agent("iiplc/0.1rc1");
    my $db   = II::DB->new();
    my $self = {
        _ua     => $ua,
        _db     => $db,
    };

    bless $self, $class;
    return $self;
}

sub get_echoes {
    my ($self, $host)    = @_;
    my $ua        = $self->{_ua};
    my $db        = $self->{_db};
    
    my @echoareas = $db->echoareas($host);
    my $echo_url = 'u/e/';
    my $msg_url  = 'u/m/';
    
    my $base64;
    my @messages_hash;
    foreach my $echo (@echoareas) {
        print STDERR "fetch $echo from $host\n";
        # Get echo message hashes
        my $req_echo = HTTP::Request->new( GET => "$host$echo_url$echo" );
        my $res_echo = $ua->request($req_echo);

        my @new;
        $db->begin();
        if ( $res_echo->is_success ) {
            my @mes = split /\n/, $res_echo->content();
            while (<@mes>) {
                if ( $_ =~ /.{20}/ ) {
                    if ( $db->check_hash( $_, $echo ) == 0 ) {
                        my $echo_hash = {
                            echo => $echo,
                            hash => $_,
                        };
                        push( @new, $echo_hash );
                    }
                }
            }
        }
        else {
            print STDERR $res_echo->status_line, "\n";
        }
        $db->commit();
        
        # Get messages
        my @msg_con;
        my $count = 0;
        while ( $count < @new ) {
            my $request = @new - $count > 50 ? 50 : @new - $count;
            my $new_messages_url = "$host$msg_url" . join ('/', map {$_->{hash}} @new[$count..$count+$request-1]) ;
            my $req_msg = HTTP::Request->new( GET => $new_messages_url );
            my $res_msg = $ua->request($req_msg);
            if ( $res_msg->is_success() ) {
                push @msg_con, split ("\n", $res_msg->content() );
            }
            else {
                print STDERR $res_msg->status_line, "\n";
            }
            $count+=$request;
        }

        # Populate hash
        while (<@msg_con>) {
            my @message = split /:/, $_;
            if ( defined( $message[1] ) ) {
                my $h = {
                    hash   => $message[0],
                    base64 => $message[1],
                };
                push( @messages_hash, $h );
            }
        }
    }
    if ( @messages_hash ) {

        # Begin transaction
        print STDERR localtime() . ": writing messages\n";
        $db->begin();

        my $c = 0;
        while ( $c < @messages_hash ) {
            my $mes_hash = $messages_hash[$c]->{hash};
            my $text = II::Enc->decrypt( $messages_hash[$c]->{base64} );
            my @parts = map {chomp;$_} split ("\n", $text);
            $db->write(
                hash    => $mes_hash,
                time    => $parts[2],
                echo    => $parts[1],
                from    => decode_utf8($parts[3]),
                to      => decode_utf8($parts[5]),
                subj    => decode_utf8($parts[6]),
                post    => decode_utf8(join ("\n", @parts[8..$#parts])),
                read    => 0,
            );
            $c++;
        }

        # Commit transaction
        $db->commit();
        print localtime() . ": messages writed to DB!\n";
    }
    return $msgs;

}

sub fetch_all
{
    my ($self) = @_;
    
    my @hosts = $self->{_db}->hosts;
    for my $h (@hosts) {
        $self->{_db}->open($h);
        $self->get_echoes($h);
    }
}

1;
