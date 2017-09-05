#!/bin/env perl

use strict;

use POSIX;
use SockUDP;

MAIN:
{
    if (scalar(@ARGV) < 1) {
        print "Usage: $0 127.0.0.1 udpPort 'msg data'\n";
        print "       $0 127.0.0.1 52526 'test smtp log port send'\n";
        exit(0);
    }

    my $client = new SockUDP();

    $client->send($ARGV[0], $ARGV[1], $ARGV[2]);
}

