#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream module and balancers with datagrams.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ dgram /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream udp/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_responses      1;
    proxy_timeout        1s;

    upstream u {
        server 127.0.0.1:%%PORT_4_UDP%%;
        server 127.0.0.1:%%PORT_5_UDP%%;
    }

    upstream u2 {
        server 127.0.0.1:%%PORT_6_UDP%% down;
        server 127.0.0.1:%%PORT_6_UDP%%;
        server 127.0.0.1:%%PORT_4_UDP%%;
        server 127.0.0.1:%%PORT_5_UDP%%;
    }

    upstream u3 {
        server 127.0.0.1:%%PORT_4_UDP%%;
        server 127.0.0.1:%%PORT_5_UDP%% weight=2;
    }

    upstream u4 {
        server 127.0.0.1:%%PORT_6_UDP%%;
        server 127.0.0.1:%%PORT_4_UDP%% backup;
    }

    server {
        listen      127.0.0.1:%%PORT_0_UDP%% udp;
        proxy_pass  u;
    }

    server {
        listen      127.0.0.1:%%PORT_1_UDP%% udp;
        proxy_pass  u2;
    }

    server {
        listen      127.0.0.1:%%PORT_2_UDP%% udp;
        proxy_pass  u3;
    }

    server {
        listen      127.0.0.1:%%PORT_3_UDP%% udp;
        proxy_pass  u4;
    }
}

EOF

$t->run_daemon(\&udp_daemon, port(4), $t);
$t->run_daemon(\&udp_daemon, port(5), $t);
$t->try_run('no stream udp')->plan(4);

$t->waitforfile($t->testdir . '/' . port(4));
$t->waitforfile($t->testdir . '/' . port(5));

###############################################################################

my @ports = my ($port4, $port5) = (port(4), port(5));

is(many(30, port(0)), "$port4: 15, $port5: 15", 'balanced');
is(many(30, port(1)), "$port4: 15, $port5: 15", 'failures');
is(many(30, port(2)), "$port4: 10, $port5: 20", 'weight');
is(many(30, port(3)), "$port4: 30", 'backup');

###############################################################################

sub many {
	my ($count, $port) = @_;
	my (%ports);

	for (1 .. $count) {
		if (dgram("127.0.0.1:$port")->io('.') =~ /(\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub udp_daemon {
	my ($port, $t) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => '127.0.0.1:' . $port,
		Reuse => 1,
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (1) {
		$server->recv(my $buffer, 65536);
		$buffer = $server->sockport();
		$server->send($buffer);
	}
}

###############################################################################
