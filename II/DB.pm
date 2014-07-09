# Copyright (c) 2014, Vasiliy Vylegzhanin <v.gadfly@gmail.com>
# Copyright (c) 2014, Difrex <difrex.punk@gmail.com>
# Some rights reserved.

package II::DB;

use strict;
use DBI;

use Config::Tiny;
use Data::Dumper;

sub new {
    my ( $class, $uid ) = @_;
    my $conf = Config::Tiny->read('config.ini');

    my $udbh = DBI->connect( "dbi:SQLite:dbname=".$conf->{server}{userdb}, "", "", {sqlite_unicode => 1} ) or die "$!";

    my $create = qq(
CREATE TABLE IF NOT EXISTS 'users'
  ('id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  'login' TEXT NOT NULL,
  'pwhash' VARCHAR(40) NOT NULL,
  'node' TEXT,
  'auth' TEXT););
    $udbh->do($create) or die "$!";
    $create = qq(
CREATE TABLE IF NOT EXISTS 'user_sub'
  ('userid' INTEGER NOT NULL,
  'areaname' TEXT NOT NULL););
    $udbh->do($create) or die "$!";

    my $self = {
        _udbh => $udbh,
    };

    return bless $self, $class;
}

sub open
{
    my ( $self, $host ) = @_;
    $host = 'dummy' unless $host;
    
    $host =~ s@^http://@@;
    $host =~ s@\?.*$@@;
    $host =~ s@[/.]@_@g;

    my $conf = Config::Tiny->read('config.ini');
    my $dbh = DBI->connect( "dbi:SQLite:dbname=".$conf->{server}{dbdir}.'/'.$host.'.db', "", "", {sqlite_unicode => 1} ) or die "$!";
    
    my $create = qq(
      CREATE TABLE IF NOT EXISTS 'messages' 
        ('id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        'echo' VARCHAR(45) NOT NULL,
        'from' TEXT NOT NULL,
        'to' TEXT,
        'subj' VARCHAR(50),
        'time' TIMESTAMP NOT NULL,
        'hash' VARCHAR(30) NOT NULL,
        'read' INT,
        'post' TEXT);
    );
    $dbh->do($create) or die "$!";
    $create = qq(
      CREATE TABLE IF NOT EXISTS 'output' 
        ('id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        'echo' VARCHAR(45) NOT NULL,
        'from' INT NOT NULL,
        'to' TEXT NOT NULL,
        'subj' VARCHAR(50),
        'sent' INT,
        'post' TEXT,
        base64 TEXT NOT NULL);
    );
    $dbh->do($create) or die "$!";
    $create = qq(
      CREATE TABLE IF NOT EXISTS 'echo' 
        ('echo' VARCHAR(45),
        'hash' VARCHAR(32)
        );
    );
    $dbh->do($create) or die "$!";
    $self->{_dbh} = $dbh;
}

sub check_hash {
    my ( $self, $hash, $echo ) = @_;
    my $dbh = $self->{_dbh};

    my $q   = "select hash from messages where hash=? and echo=?";
    my $sth = $dbh->prepare($q);
    $sth->execute($hash, $echo);

    if ( my @h = $sth->fetchrow_array() ) {
            return 1;
    }
    return 0;
}

sub begin {
    my ($self) = @_;
    $self->{_udbh}->do('BEGIN');
    $self->{_dbh}->do('BEGIN');
}

sub commit {
    my ($self) = @_;
    $self->{_udbh}->do('COMMIT');
    $self->{_dbh}->do('COMMIT');
}

sub write_echo {
    my ( $self, %data ) = @_;
    my $dbh = $self->{_dbh};
    
    my $stmt = "INSERT INTO 'messages' (".
        join (',', map {"'$_'"} keys %data).
        ") VALUES (".
        join (',', ("?")x(scalar keys %data)).
        ");";
    my $sth = $dbh->prepare($stmt);
    $sth->execute(values %data);
}

sub write_out {
    my ( $self, %data ) = @_;
    
    my $u = $self->user($data{from});
    $self->open($u->{node});
    my $dbh = $self->{_dbh};

    my $stmt = "INSERT INTO 'output' (".
        join (',', map {"'$_'"} keys %data).
        ") VALUES (".
        join (',', ("?")x(scalar keys %data)).
        ");";
    my $sth = $dbh->prepare($stmt);
    $sth->execute(values %data);
}

sub update_out {
    my ( $self, $id ) = @_;
    my $dbh = $self->{_dbh};

    my $q   = "update output set sent=1 where id=?";
    my $sth = $dbh->prepare($q);
    $sth->execute($id);
}

sub write {
    my ( $self, %data ) = @_;
    my $dbh = $self->{_dbh};
    
    my $stmt = "INSERT INTO 'messages' (".
        join (',', map {"'$_'"} keys %data).
        ") VALUES (".
        join (',', ("?")x(scalar keys %data)).
        ");";
    my $sth = $dbh->prepare($stmt);
    $sth->execute(values %data);
}

sub select_out {
    my ($self, $uid) = @_;
    my $dbh = $self->{_dbh};

    my $q = "select * from 'output' where `sent`=0 and `from`=?";
    my $sth = $dbh->prepare($q);
    $sth->execute($uid);

    my @posts;
    while ( my $m = $sth->fetchrow_hashref() ) {
        push( @posts, $m );
    }
    return @posts;
}

sub host_out {
    my ($self) = @_;
    my $dbh = $self->{_dbh};

    my $q = "select `id`, `from`, `base64` from 'output' where `sent`=0";
    my $sth = $dbh->prepare($q);
    $sth->execute;

    my @posts;
    while ( my $m = $sth->fetchrow_hashref() ) {
        push( @posts, $m );
    }
    return @posts;
}

sub select_index {
    my ( $self, $uid, $limit ) = @_;
    my $dbh = $self->{_dbh};

    my @sub = @{$self->user($uid)->{sub}};
    my $q = "select hash from messages WHERE echo IN (".join(',', ('?')x@sub).") order by time desc limit ?";

    my $sth = $dbh->prepare($q);
    $sth->execute(@sub, $limit);

    return (map {$_->[0]} @{$sth->fetchall_arrayref()});
}

sub select_subj {
    my ( $self, $echo ) = @_;

}

# Select user messages
sub select_user {
    my ( $self, $user ) = @_;
    my $dbh = $self->{_dbh};

    my $q
        = "select from, to, subj, time, echo, post, hash from messages where `from`='$user' order by time desc";

    my $sth = $dbh->prepare($q);
    $sth->execute();

    my @posts;
    while ( my @hash = $sth->fetchrow_array() ) {
        my ( $from, $to, $subj, $time, $echo, $post, $h ) = @hash;
        my $data = {
            from => "$from",
            to   => "$to",
            subj => "$subj",
            time => $time,
            echo => "$echo",
            post => "$post",
            hash => $h,
        };
        push( @posts, $data );
    }

    return @posts;
}

sub from_me {
    my ( $self, $config ) = @_;
    my $dbh  = $self->{_dbh};
    my $nick = $config->{nick};

    # print Dumper($config);
    # print "NICK: $nick\n";

    my $q
        = "select from, to, subj, time, echo, post, hash from messages where `from`='$nick'";

    my $sth = $dbh->prepare($q);
    $sth->execute();

    my @posts;
    while ( my @hash = $sth->fetchrow_array() ) {
        my ( $from, $to, $subj, $time, $echo, $post, $h ) = @hash;
        my $data = {
            from => "$from",
            to   => "$to",
            subj => "$subj",
            time => $time,
            echo => "$echo",
            post => "$post",
            hash => $h,
        };
        push( @posts, $data );
    }

    return @posts;
}

sub thread {
    my ( $self, $subj, $echo ) = @_;
    my $dbh = $self->{_dbh};

    my $q
        = "select from, to, subj, time, echo, post, hash from messages where echo='$echo' and subj like '%$subj%' order by time";

    my $sth = $dbh->prepare($q);
    $sth->execute();

    my @posts;
    while ( my @hash = $sth->fetchrow_array() ) {
        my ( $from, $to, $subj, $time, $echo, $post, $h ) = @hash;
        my $data = {
            from => "$from",
            to   => "$to",
            subj => "$subj",
            time => $time,
            echo => "$echo",
            post => "$post",
            hash => $h,
        };
        push( @posts, $data );
    }

    return @posts;
}

sub echoes {
    my ( $self, $uid, $echo ) = @_;
    my $dbh = $self->{_dbh};

    my $q
        = "select * FROM 'messages' where echo=? order by time desc";

    my $sth = $dbh->prepare($q);
    $sth->execute($echo);

    my @posts;
    while ( my $hash = $sth->fetchrow_hashref() ) {
        push( @posts, $hash );
    }
    
    return @posts;
}

sub to_me {
    my ( $self, $config ) = @_;
    my $dbh  = $self->{_dbh};
    my $nick = $config->{nick};

    # print Dumper($config);
    # print "NICK: $nick\n";

    my $q
        = "select from, to, subj, time, echo, post, hash from messages where to='$nick'";

    my $sth = $dbh->prepare($q);
    $sth->execute();

    my @posts;
    while ( my @hash = $sth->fetchrow_array() ) {
        my ( $from, $to, $subj, $time, $echo, $post, $h ) = @hash;
        my $data = {
            from => "$from",
            to   => "$to",
            subj => "$subj",
            time => $time,
            echo => "$echo",
            post => "$post",
            hash => "$h",
        };
        push( @posts, $data );
    }

    return @posts;
}

sub select_new {
    my ( $self, @hashes ) = @_;
    my $dbh = $self->{_dbh};

    my $q
        = "select * from messages where hash IN (".join(',',('?')x@hashes).") order by time desc;";

    my $sth = $dbh->prepare($q);
    $sth->execute(@hashes);
    
    my @mesg;
    while (my $m = $sth->fetchrow_hashref()){
        push @mesg, $m;
    }
    return @mesg;
}

sub message {
    my ( $self, $hash ) = @_;
    my $dbh = $self->{_dbh};

    my $q
        = "select * from messages where hash=?";

    my $sth = $dbh->prepare($q);
    $sth->execute($hash);
    
    return $sth->fetchrow_hashref();
}

sub add_user
{
    my ( $self, %user ) = @_;
    my $dbh = $self->{_udbh};
    
    my $q = "INSERT INTO users ('login', 'pwhash', 'node', 'auth')".
        " VALUES (?, ?, ?, ?)";
    my $sth = $dbh->prepare($q) or die $dbh->errstr;
    return $sth->execute ($user{login}, $user{pwhash}, $user{node}, $user{auth});
}

sub check_user
{
    my ( $self, $user ) = @_;
    my $dbh = $self->{_udbh};
    
    my $sth = $dbh->prepare('SELECT id FROM users WHERE login=?') or die "$!";
    $sth->execute ($user);
    my @res = $sth->fetchrow_array;
    return $res[0] if (@res);
    return undef;
}

sub auth_user
{
    my ( $self, $login, $hash ) = @_;
    my $dbh = $self->{_udbh};
    
    my $sth = $dbh->prepare("SELECT id FROM users WHERE login=? AND pwhash=?") or die "$!";
    $sth->execute ($login, $hash);
    if ( my @res = $sth->fetchrow_array() ) {
        return $res[0];
    } 
    return undef;
}

sub update_user
{
    my ( $self, $user ) = @_;
    my $dbh = $self->{_udbh};

    $self->begin;

    my $sq = $dbh->prepare ("UPDATE users SET node=?, auth=? WHERE id=?");
    $sq->execute($user->{node}, $user->{auth}, $user->{id});
    
    $sq = $dbh->prepare ('DELETE FROM user_sub WHERE userid=?');
    $sq->execute($user->{id});
    
    $sq = $dbh->prepare ('INSERT INTO user_sub (userid, areaname) VALUES (?, ?)');
    for my $ea (@{$user->{sub}}) {
        $sq->execute($user->{id}, $ea);
    }
    $self->commit;
    
    return $self->user($user->{id});
}

sub user
{
    my ( $self, $uid ) = @_;
    my $dbh = $self->{_udbh};

    my $sq = $dbh->prepare ("SELECT * from users WHERE id=?");
    $sq->execute($uid);
    my $user = $sq->fetchrow_hashref();
    $sq = $dbh->prepare('SELECT areaname FROM user_sub WHERE userid=?');
    $sq->execute($uid);
    $user->{sub} = [map {$_->[0]} @{$sq->fetchall_arrayref()}];
    return $user;
}

sub users
{
    my ( $self ) = @_;
    my $dbh = $self->{_udbh};

    my $sq = $dbh->do ("SELECT * from users");
    die Dumper $sq->fetchall_hashref();
}

sub echoareas
{
    my ( $self, $host ) = @_;
    my $db = $self->{_udbh};
    
    my $sq = $db->prepare ('SELECT DISTINCT user_sub.areaname FROM user_sub INNER JOIN users ON user_sub.userid = users.id WHERE users.node=?');
    $sq->execute($host);

    return (map {$_->[0]} @{$sq->fetchall_arrayref()});
}

sub hosts
{
    my ( $self, $host ) = @_;
    my $db = $self->{_udbh};
    
    my $sq = $db->prepare ('SELECT DISTINCT node FROM users');
    $sq->execute;
    my @res = (map {$_->[0]} @{$sq->fetchall_arrayref()});
    
    return @res;
}
1;
