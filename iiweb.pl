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

helper resubj => sub {
    my ($self, $subj) = @_;
    unless ($subj =~ /^re:/i) {
        $subj = 'Re: '.$subj;
    }
    return $subj;
};

helper format_mesg => sub {
    my ($self, $post) = @_;

    $post =~ s/</&lt;/g;
    $post =~ s/>/&gt;/g;
    $post =~ s/&gt;(.+)/<font color='green'>>$1<\/font>/g;
    $post =~ s/--/&mdash;/g;
    $post =~ s/.?\*(.+)\*.?/<b>$1<\/b>/g;
    $post =~ s/^$/<br>\n/g;
    $post =~ s/(.?)\n/$1<br>\n/g;
    $post
        =~ s/(https?:\/\/.+\.(jpg|png|gif))/<a href="$1"><img src="$1" width="15%" height="15%" \/><\/a>/g;
    $post
        =~ s/(https?:\/\/.+\.(JPG|PNG|GIF))/<a href="$1"><img src="$1" width="15%" height="15%" \/><\/a>/g;
    return $post;
};

under sub {
    my $self = shift;
    my $uid = $self->session('uid');
    if (my $m = $self->session('message')) {
        $self->stash(message => $m);
        delete $self->session->{message};
    }
    if (my $e = $self->session('error')) {
        $self->stash(error => $e);
        delete $self->session->{error};
    }
    if ($uid){
        my $user = $db->user($uid);
        $db->open($user->{node});
        $self->stash( echoindex => $user->{sub} );
        return 1;
    }
    return 1 if $self->url_for->path =~ m|/login|;
    $self->redirect_to('login');
    return 0;
};

get '/' => sub {
    my $self = shift;
    my @hashes = $db->select_index($self->session('uid'), 50);
    $self->stash (messages => [$db->select_new(@hashes)]);
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

get '/new/#area' => sub {
    my $self = shift;
    if ($self->param('repto')) {
        $self->stash(repto => $db->message($self->param('repto')));
    }
    $self->render;
} => 'new';

post '/enc' => sub {
    my $self = shift;
    
    my $enc = II::Enc->new( $config, {
            from => $self->session('uid'),
            echo => $self->param('echo'),
            to   => $self->param('to'),
            subj => $self->param('subj'),
            post => $self->param('post'),
            hash => $self->param('repto') ? $self->param('repto') : undef,
        } );
    if ($enc->encode() == 0) {
        $self->session(message => 'Сообщение сохранено');
    } else {
        $self->session(error => 'Не удалось сохранить сообщение');
    }
    return $self->redirect_to('index');
} => 'enc';

get '/out' => sub {
    my $self = shift;
    $self->stash(messages => [$db->select_out($self->session('uid'))]);
    $self->render;
} => 'out';

get '/push' => sub {
    my $self = shift;
    my $send = II::Send->new;
    $send->push_all;
    $self->render(text => 'pushed');
} => 'push';

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

#app->secrets (['some secret passphrase']);
app->start;
