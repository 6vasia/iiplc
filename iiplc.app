#!/usr/bin/perl
# Copyright © 2014 Difrex <difrex.punk@gmail.com>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the COPYING file for more details.

# This program is free software. It comes without any warranty, to
# the extent permitted by applicable law. You can redistribute it
# and/or modify it under the terms of the Do What The Fuck You Want
# To Public License, Version 2, as published by Sam Hocevar. See
# http://www.wtfpl.net/ for more details.

use strict;
use warnings;

use Plack::Builder;
use Plack::Request;
use Plack::Response;

use II::Config;
use II::Get;
use II::Send;
use II::Render;
use II::DB;
use II::Enc;

use Digest::SHA1 qw(sha1_hex);
# Debug
use Data::Dumper;

my $c      = II::Config->new();
my $config = $c->load();

my $GET    = II::Get->new($config);
my $render = II::Render->new();

sub echo
{
    my $env = shift;
    unless ($env->{'psgix.session'}{user_id}) {
        return [ 302, [ 'Location' => '/login' ], [] ]
    }
    
    my $req = Plack::Request->new($env);

    my $echo = $req->param('echo');
    my $view = $req->param('view');

    my $echo_messages = $render->echo_mes( $echo, $view );

    return [ 200, [ 'Content-type' => 'text/html' ], ["$echo_messages"], ];
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

sub get
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

sub new
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

builder {
    enable 'Session';
    enable 'Auth::Form', no_login_page => 1, authenticator => sub { 
        my ($login, $passwd, $env) = @_;
        my $db = II::DB->new();
        return $db->auth_user($login, sha1_hex($passwd));
    };
    enable 'Static', path => '^/static/', root => './';
    mount '/'       => \&root;
    mount '/e'      => \&echo;
    mount '/s'      => \&thread;
    mount '/u'      => \&user;
    mount '/me'     => \&me;
    mount '/tree'   => \&tree;
    mount '/get'    => \&get;
    mount '/send'   => \&send_mesg;
    mount '/enc'    => \&enc;
    mount '/out'    => \&out;
    mount '/push'   => \&push_mesg;
    mount '/new'    => \&new;
    mount '/login'  => \&login;
    mount '/reg'    => \&register;
    mount '/config' => \&config;
};
