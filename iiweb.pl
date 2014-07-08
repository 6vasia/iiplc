#!/usr/bin/env perl
# Copyright (c) 2014, Vasiliy Vylegzhanin <v.gadfly@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer. 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use warnings;
use utf8;

use Mojolicious::Lite;
use Config::Tiny;

use II::Get;
use II::Send;
use II::Render;
use II::DB;
use II::Enc;

use Digest::SHA1 qw(sha1_hex);
# Debug
use Data::Dumper;

my $config = Config::Tiny->read('config.ini');

my $GET    = II::Get->new;
my $render = II::Render->new;
my $db = II::DB->new;

under '/' => sub {
    my $self = shift;
    my $uid = $self->session('uid');
    
    if ($uid){
        my $user = $db->user($uid);
        $db->open($user->{node});
        return 1;
    }
    return 1 if $self->url_for->path =~ m|/login|;
    return $self->redirect_to('login');
};

get '/' => sub {
    my $self = shift;
    $self->render;
} => 'index';

get '/login' => sub {
    my $self = shift;
    
    my $email = $self->param('email') || '';
    my $pass = $self->param('pass') || '';
    
    if (my $uid = $db->auth_user($email, sha1_hex($pass))){
        $self->session(uid => $uid);
        return $self->redirect_to('index');
    }
    
    $self->render;
} => 'login';

get '/logout' => sub {
    my $self = shift;
    $self->session(expires => 1);
    $self->redirect_to('index');
} => 'logout';

any '/config' => sub {
    my $self = shift;

    my $user = $db->user($self->session('uid'));
    if ($self->param('update')){
        my $upd = {
                id => $self->session('uid'),
                node => $self->param('node'),
                auth => $self->param('auth'),
                sub => [map {s/^\s+//;s/\s+$//;$_} split("\n", $self->param('sub'))]
            };
        $user = $db->update_user($upd);
        $db->open($user->{node});
    }
    $user->{sub} = join ("\n", @{$user->{sub}});
    $self->stash (user => $user);
    $self->render;
} => 'config';

get '/echo/#area' => sub {
    my $self = shift;
    
    my $area = $self->param('area');
    my $view = $self->param('view');

    my @messages = $db->echoes($self->session('uid'), $area);
    
    $self->stash( messages => \@messages);
    $self->render;
} => 'echo';

get '/get' => sub {
    my $self = shift;
    $GET->fetch_all;
    $self->redirect_to('index');
};

sub thread
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req = Plack::Request->new($env);

    my $subg = $req->param('subg');
    my $echo = $req->param('echo');

    my $thread = $render->thread( $subg, $echo );

    return [ 200, [ 'Content-type' => 'text/html' ], ["$thread"], ];
};

sub get_mesg
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }
    my $msgs    = $GET->get_echo();
    my $new_mes = $render->new_mes($msgs);
    return [ 200, [ 'Content-type' => 'text/html' ], ["$new_mes"], ];
};

sub root
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }
    my $index = $render->index($config);
    return [ 200, [ 'Content-type' => 'text/html' ], [$index], ];
};

sub me{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }
    my $messages = $render->to_me($config);
    return [ 200, [ 'Content-type' => 'text/html' ], [$messages], ];
};

sub tree
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }
    my $subges = $render->tree($config);
    return [ 200, [ 'Content-type' => 'text/html' ], ['Дерево'], ];
};

sub new_mesg
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req  = Plack::Request->new($env);
    my $echo = $req->param('echo');

    my $send = $render->send_new($echo);
    return [ 200, [ 'Content-type' => 'text/html' ], [$send], ];
};

sub send_mesg
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req  = Plack::Request->new($env);
    my $hash = $req->param('hash');
    my $send = $render->send($hash);

    return [ 200, [ 'Content-type' => 'text/html' ], [$send], ];
};

sub enc
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        $env->{'psgix.session'}{redir_to} = '/enc';
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req = Plack::Request->new($env);

    # Get parameters
    my $echo = $req->param('echo');
    my $to   = $req->param('to');
    my $post = $req->param('post');
    my $subg = $req->param('subg');
    my $hash = $req->param('hash');
    my $time = time();

    print Dumper($config);
    my $data = {
        echo => $echo,
        to   => $to,
        from => $config->{nick},
        subg => $subg,
        post => $post,
        time => $time,
        hash => $hash,
    };

    my $enc = II::Enc->new( $config, $data );
    $enc->encode() == 0 or die "$!\n";

    return [ 302, [ 'Location' => '/out' ], [], ];
};

sub out
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }
    my $out = $render->out();

    return [ 200, [ 'Content-type' => 'text/html' ], [$out], ];
};

# Push message to server
sub push_mesg
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req = Plack::Request->new($env);

    my $echo   = $req->param('echo');
    my $base64 = $req->param('base64');
    my $hash   = $req->param('hash');

    my $s = II::Send->new( $config, $echo, $base64 );
    $s->send($hash);

    my $db = II::DB->new();
    $db->update_out($hash);

    return [ 302, [ 'Location' => "/e?echo=$echo" ], [], ];
};

# Messages from user
sub user 
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req      = Plack::Request->new($env);
    my $user     = $req->param('user');
    my $mes_from = $render->user($user);

    return [ 200, [ 'Content-type' => 'text/html' ], [$mes_from], ];
};

sub login
{
    my $env = shift;
    my $login = $render->login($env->{'Plack::Middleware::Auth::Form.LoginForm'});
    
    return [ 200, [ 'Content-type' => 'text/html' ], [$login], ];
}

sub register
{
    my $env = shift;
    my $req = Plack::Request->new($env);

    my $error = "";
    my $email = $req->param('email');
    my $pass1 = $req->param('pass1');
    my $pass2 = $req->param('pass2');

    if ($email) {
        unless (defined $pass1 and $pass1 ne '') {
            $error = 'Пустой пароль недопустим';
        } else {
            if ($pass1 ne $pass2) {
                $error = 'Пароль и подтверждение не совпадают';
            } else {
                unless ($email =~ /^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$/) {
                    $error = 'Мне не нравится ваш e-mail';
                } else {
                    # at last
                    my $db = II::DB->new();
                    if ($db->check_user ($email)) {
                        $error = 'E-mail уже используется';
                    } else {
                        if ($db->add_user(login => $email, pwhash => sha1_hex($pass1))) {
                            $env->{'psgix.session'}{user_id} = $email;
                            return return [ 302, [ 'Location' => '/config' ], [] ]
                        } else {
                            $error = 'Что-то сломалось :(';
                        }
                    }
                }
            }
        }
    }
    my $reg_form = $render->register($error);
    
    return [ 200, [ 'Content-type' => 'text/html' ], [$reg_form], ];
}

sub config
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        $env->{'psgix.session'}{redir_to} = '/config';
        return [ 302, [ 'Location' => '/login' ], [] ]
    }

    my $req = Plack::Request->new($env);

    my $error = "";
    my $node = $req->param('node');
    my $auth = $req->param('auth');
    my $sub = $req->param('sub');
    
    my $conf_form = $render->config($error);

    return [ 200, [ 'Content-type' => 'text/html' ], [$conf_form], ];
}

#app->secrets (['some secret passphrase']);
app->start;
