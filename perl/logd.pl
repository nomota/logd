#!/usr/local/mobigen/CrediMail/perl/bin/perl
# ------------------------------------------------------------------------
# shield_log.d --
#   UDP ·Î±× µ¥¸ó
#
# Author: Nomota KIM Hiongun, nomota@mobigen.com
#         All rights reserved. (c) Mobigen Inc.
#
# Updates:
#   2004/02/05 dmail.conf°¡ ¾øÀÌ svc.conf¸¸À¸·Îµµ LOG_DIR, LOG_PORT°ªÀ»
#              ³Ö¾î ÁÙ ¼ö ÀÖµµ·Ï ÇÔ.
#   2002/06/15 smtp_log.d¸¦ shield_log.d·Î º¯°æ
#   2002/04/07 ¸ÖÆ¼Æ÷Æ® ´ë±â ±â´ÉÀ» MyConfig¿Í ¿¬µ¿ÇÔ.
#   2002/04/06 ¸ÖÆ¼Æ÷Æ®¸¦ ´ë±âÇÏ¸é¼­, ¿©·¯°¡Áö Á¾·ùÀÇ ·Î±×¸¦ µ¿½Ã¿¡
#              ³²±æ ¼ö ÀÖµµ·Ï ¼öÁ¤
#   2002/03/07 ±âº» confÆÄÀÏÀ» ~/conf/smtp_gw.conf·Î ¹Ù²Þ
#   2001/11/28 smtp_gw.log ¶ó´Â ÆÄÀÏ ÀÌ¸§À» smtp_gw_YYYY.MM.DD.log ·Î ¹Ù²Þ.
#   2001/11/08 check_descriptors_limit() Á¦°Å, BSD::Resource·Î Ä¡È¯
#   2001/09/20 initially created.
# ------------------------------------------------------------------------
use strict;

use POSIX;
use Carp;
use SockUDP;
use IO::Socket::INET;
use IO::Select;
use Tie::RefHash;
use VERSION;
require 'flush.pl';

$main::flush_duration = 1;
$main::debug = 0;

$main::LOG_DIR = "/KTMAIL/log";

$main::LOG_PORT = [];
$main::LOG_PORT->[0] = "SMTP:52526";
$main::LOG_PORT->[1] = "POP3:52527";

my $DEBUG = 0;
sub ASSERT { if (! $_[0]) { Carp::confess("ASSERT\n"); } }

END { use POSIX; POSIX::_exit(0); }
BEGIN { $ENV{PATH} = '/usr/bin;/bin;/usr/sbin/;/sbin'; }
sub REAPER()
{
    my $waitedpid = wait();

    $SIG{CHLD} = \&REAPER;  # loathe sysV
}

sub new_fh() { local(*F); return *F; }

sub do_flush($)
{
    my ($log_server) = @_;

    #
    # ·Î±× ¼­¹ö ÇÏ³ª°¡ °¡Áö°í ÀÖ´Â ³»ºÎ Á¤º¸.
    #
    # $log_server = { SUBDIR => 'SHIELD_LOG',
    #                 PORT => 52526,
    #                 SOCK => $SockUDP,
    #                 FH => open_log_file_handle,
    #                 MSGS => [$msg1, $msg2, $msg3, ...] # flushÇÏ±â Àü ·Î±×
    #               }
    #
    # $msg = [$host, $ip, $msg_string]
    #

    ASSERT(defined $log_server);
    ASSERT(defined $log_server->{SUBDIR}); # SHIELD_LOG
    ASSERT(defined $log_server->{PORT});   # 52526
    ASSERT(defined $log_server->{MSGS});   # [[$ip,$port,$msg], ...]
    ASSERT(@{$log_server->{MSGS}} > 0);

    #
    # ·Î±× µð·ºÅä¸®°¡ Á¦´ë·Î ÀÖ¾î¾ß ÇÔÀ» º¸ÀåÇØ¾ß ÇÔ.
    # µð·ºÅä¸®°¡ ¾øÀ¸¸é »õ·Î ¸¸µç´Ù.
    #
    # ¸¸¾à ·Î±× ÆÄÀÏÇÚµéÀÌ ¿­·Á ÀÖ¾ú´Âµ¥, ÆÄÀÏÀÌ Á¸ÀçÇÏÁö ¾ÊÀ¸¸é,
    # Áö¿öÁø °æ¿ìÀÓ. ´Ý°í »õ·Î ¿­¾î¾ß ÇÑ´Ù.
    ASSERT(defined $main::LOG_DIR);   # /usr/local/mobigen/CrediShield/logs
    my $log_path = "$main::LOG_DIR/$log_server->{SUBDIR}";

    $main::cur_time = time();

    # ³¯Â¥º°·Î µð·ºÅä¸®¸¦ µû·Î ¸¸µë.
    #                           YYYYmmdd
    my $today = POSIX::strftime("%Y%m%d", localtime($main::cur_time));

    # ½Ã°£º°·Î ·Î±× ÆÄÀÏÀÌ µû·Î »ý±è.
    #                               HH
    my $cur_hour = POSIX::strftime("%H", localtime($main::cur_time));
    my $readable_time = POSIX::strftime("%H:%M:%S", localtime($main::cur_time));

    if (! -e "$log_path/$today/$cur_hour") {

        umask(0000);

        mkdir("$main::LOG_DIR", 0777);
        mkdir("$log_path", 0777);
        mkdir("$log_path/$today", 0777);

        if (! -e "$log_path/$today") {
            die "mkdir '$log_path/$today' fail";
        }

        if (defined $log_server->{FH}) {
            close($log_server->{FH});
            delete $log_server->{FH};
        }

        my $fh = new_fh();
        $log_server->{FH} = $fh;

        open($fh, ">> $log_path/$today/$cur_hour");
    }


    if (! defined $log_server->{FH}) {

        # ÆÄÀÏÀº Á¸ÀçÇÏ´Âµ¥, ¿­·ÁÀÖÁö ¾ÊÀº °æ¿ì
        # -- Á×¾ú´Ù°¡ »ì¾Æ³µÀ» °æ¿ì, »õ·Î ¿­¾î¾ß ÇÔ.

        my $fh = new_fh();
        $log_server->{FH} = $fh;
        umask(0000);
        open($fh, ">> $log_path/$today/$cur_hour");
    }

    #
    # ¿­·ÁÀÖ´Â ÆÄÀÏ ÇÚµé¿¡ ´ë°í ·Î±× ³»¿ªÀ» ±â·ÏÇÏ±â¸¸ ÇÏ¸é µÊ.
    #

    ASSERT(defined $log_server->{FH});

    my $fh = $log_server->{FH};

    foreach my $msg (@{$log_server->{MSGS}}) {
        # $msg->[0] ·Î±×¸¦ ¿äÃ»ÇÑ ¼­¹ö IP
        # $msg->[1] Æ÷Æ®¹øÈ£ (UDP·Î ÀÓ½ÃÇÒ´çµÈ ¹øÈ£µéÀÓ)
        # $msg->[2] ½ÇÁ¦ ·Î±×·Î ³²±æ ¸Þ½ÃÁö
        # print F "$msg->[0] $msg->[2]";
        # ÀÌºÎºÐ¿¡¼­ localserver¸¦ ÂïÁö ¸»°í ... timeÀ¸·Î ´ëÄ¡

        warn "$readable_time $msg->[2]" if $DEBUG;

        print $fh "$readable_time $msg->[2]";

        if (substr($msg->[2], -1) ne "\n") {
            print $fh "\n";
        }
    }

    $log_server->{MSGS} = [];

    flush($fh); # Ç×»ó flush()ÇÏ´Â °ÍÀÌ ¸Â´ÂÁö Performance¸¦ º¸°í µûÁ® ºÁ¾ß ÇÔ.
}

sub handle_read($)
{
    my ($log_server) = @_; # ¸Þ½ÃÁö°¡ µµÂøÇÑ Æ÷Æ®¿¡ ÇØ´çÇÏ´Â ·Î±× ¼­¹ö

    # $log_server = { SUBDIR => 'SHIELD_LOG',
    #                 PORT => 52526,
    #                 SOCK => $SockUDP,
    #                 MSGS => [$msg1, $msg2, $msg3, ...] # flushÇÏ±â Àü ·Î±×
    #               }

    my $udp_sock = $log_server->{SOCK};

    my ($host, $port, $msg) = $udp_sock->recv(); # µ¥ÀÌÅ¸¸¦ ÀÐ¾îµéÀÎ´Ù.

    if (! defined $msg) {
        warn "recv() fail." if $DEBUG;
        return;
    }

    warn "[$host, $port, $msg]" if $DEBUG;

    # Á¤»óÀûÀ¸·Î ÀÐÇûÀ¸¸é, ÇØ´ç¼­¹öÀÇ ¹öÆÛ¿¡ ½×¾Æ µÐ´Ù.
    push @{$log_server->{MSGS}}, [$host, $port, $msg];

    # 2010.10.02 nomota LOG_MIRROR added
    if (defined $main::LOG_MIRROR_IP) {
warn "LOG_MIRROR";
        if (defined $main::LOG_MIRROR_IP->{$log_server->{SUBDIR}}) {
            my $mirror_ip = $main::LOG_MIRROR_IP->{$log_server->{SUBDIR}};
warn "mirror_ip:$mirror_ip";
            $udp_sock->send($mirror_ip, $log_server->{PORT}, $msg);
        }
    }
}


sub handle_mon_read($)
{
    my ($log_mon_server) = @_;

    $SIG{CHLD} = 'IGNORE';

    if (fork() == 0) {
      my $sock = undef;
      eval {
        $SIG{ALRM} = sub {
            die 'TIMEOUT ERROR';
        };
        alarm(2);

        warn "log_mon_server->{STATUS}: $log_mon_server->{STATUS}" if $DEBUG;

        my $listen_sock = $log_mon_server->{SOCK};
        $sock = $listen_sock->accept();
        if (! $sock) {
            warn "accept() failed: $!" if $DEBUG;
            exit(0);
        }

        warn "sock: $sock accepted" if $DEBUG;

        print $sock "+OK WELCOME CrediMail logd.exe-$main::VERSION\r\n";

        while (my $line = <$sock>) {
            $line =~ s/\r?\n//g; # chop

            if ($line =~ /^QUIT/i) {
                print $sock "+OK QUIT\r\n";
                last;
            }

            if ($line =~ /^HELP/i) {
                print $sock "+OK HELP TEXT FOLLOWS\r\n";
                print $sock "* HELP\r\n";
                print $sock "* QUIT\r\n";
                print $sock "* VERSION\r\n";
                print $sock "* STAT\r\n";
                print $sock "+OK HELP DONE\r\n";
                next;
            }

            if ($line =~ /^VERSION/i) {
                print $sock "+OK VERSION: $main::VERSION\r\n";
                next;
            }

            if ($line =~ /^STAT/i) {
                print $sock "-ERR STAT not yet implemented.\r\n";
                next;
            }

            print $sock "-ERR UNKNOWN CMD [$line]\r\n";
        }

        warn "sock($sock)->close()" if $DEBUG;

        $sock->close(); undef $sock;

        alarm(0);
      };

        if (defined($sock)) {
            $sock->close(); undef $sock;
        }
        exit(0);
    }
}

sub main_loop()
{
    ASSERT(defined $main::SELECT);

    # ÀüÇüÀûÀÎ ¸ÖÆ¼ ¼ÒÄÏ ÇÚµé¸µ ·çÆ¾

    my $last_flushtime = time(); # ¸¶Áö¸·À¸·Î flushÇÑ ½Ã°£À» ±â·Ï

    while (1) {
        $main::cur_time = time();

        ### WAIT ################################

        my @ready_socks = $main::SELECT->can_read(1.0);

        ### READ ################################

        foreach my $udp_sock (@ready_socks) {
            # °¢°¢ÀÇ ÀÐ±â°¡´ÉÇÑ ¼ÒÄÏ º°·Î, ·Î±× ¸Þ½ÃÁö¸¦ ÀÐ¾î¼­
            # ¼­¹öÀÇ MSGS ¹öÆÛ¿¡ ½×¾Æ µÐ´Ù.

            my $log_server = $main::SOCK_SERVERS->{$udp_sock};

            ASSERT(defined $log_server);

            # ·Î±× ¸ð´ÏÅÍ¸µ ¼­¹ö·Î Á¢¼ÓÀÌ µé¾î ¿À¸é º°µµ Ã³¸®ÇÑ´Ù
            if ($log_server == $main::log_mon_server) {
                handle_mon_read($log_server);
            } else {
                handle_read($log_server);
            }
        } # foreach

        ### WRITE ###############################

        # ÀÏÁ¤±â°£ ÁÖ±â·Î, ¸Þ¸ð¸®¿¡ ½×ÀÎ ·Î±×¸¦ ÆÄÀÏ·Î flush½ÃÅ²´Ù.
        if (($main::cur_time - $last_flushtime) >= $main::flush_duration) {
            #
            # °¢°¢ÀÇ Æ÷Æ®¿¡ ÇØ´çÇÏ´Â ·Î±× ¼­¹ö º°·Î,
            # ÇÃ·¯½¬ ÇÒ °ÍÀÌ ÀÖ´Â °æ¿ì¿¡¸¸ flush¸¦ È£ÃâÇÑ´Ù.
            #
            foreach my $port (keys %{$main::LOG_SERVERS}) {
                my $log_server = $main::LOG_SERVERS->{$port};

                ASSERT(defined $log_server);

                if (@{$log_server->{MSGS}} > 0) {
                    do_flush($log_server);
                }
            }

            $last_flushtime = $main::cur_time;
        } # if
    } # while (1)
}


sub run_log_d()
{
    #
    # ¿©·¯°³ÀÇ ·Î±×¼­¹ö°¡ ÇÑ ÇÁ·Î¼¼½º ¼Ó¿¡ °øÁ¸ÇÒ ¼ö ÀÖµµ·Ï ¸¸µç ÀÚ·á±¸Á¶:
    #
    #           °¢°¢ÀÇ ·Î±× ¼­¹ö´Â, µé¾î¿À´Â ¸Þ½ÃÁöÀÇ Æ÷Æ®¹øÈ£·Î ±¸ºÐµÈ´Ù.
    #
    # $main::LOG_SERVERS = { $port => $log_server, $port => $log_server, ... }
    #
    # { $port => { SUBDIR => 'SHIELD_LOG',
    #              PORT => 52526,
    #              SOCK => $SockUDP,
    #              MSGS => [$msg1, $msg2, $msg3, ...] # flushÇÏ±â Àü ·Î±×
    #             }
    # }
    #
    # ¼ÒÄÏÀ» ¾Ë¾ÒÀ» ¶§, ÇØ´ç ·Î±×¼­¹ö¸¦ Ã£¾Æ³»±â À§ÇÑ ÀÎµ¦½Ì ÇØ½¬
    # $main::SOCK_SERVERS = { $sock => $log_server, $sock => $log_server, ... }
    #

    warn "FLUSH_DURATION: $main::flush_duration" if $DEBUG;

## smtp_gw.conf¸¦ ./smtp_gw.conf¿¡¼­ ¸øÃ£¾ÒÀ»¶§¿¡ ¿¡·¯ ¹ß»ý. »èÁ¦
## ASSERT¹®À¸·Î ´ëÃ¼

    ASSERT(defined($main::LOG_PORT));

    $main::LOG_SERVERS = {}; # ¸ðµç ·Î±× ¼­¹ö¿¡ ÇØ´ç

    # string/integer°¡ ¾Æ´Ñ socket reference¸¦ ÇØ½¬ÀÇ Å°·Î ¾²±â À§ÇÑ ¹æ¹ý.
    # Tie::RefHash¿¡ ÇØ½¬¸¦ Å¸ÀÌ½ÃÄÑ¼­ ¾²¸é µÊ.
    my %sock_servers = ();
    tie %sock_servers, 'Tie::RefHash';
    $main::SOCK_SERVERS = \%sock_servers;

  {
    # 2004/01/12 ·Î±× ¼­¹ö ÀÚÃ¼¸¦ ¸ð´ÏÅÍ¸µ ÇÏ±â À§ÇØ¼­
    #            ·Î±× ¼­¹ö°¡ Æ¯Á¤ÇÑ TCP Æ÷Æ® ÇÏ³ª¸¦ listeningÇÏ°í
    #            ÀÖµµ·Ï ¸¸µç´Ù.
    ASSERT(defined $main::svc_conf->{LOG_MON_PORT});

    my $log_mon_sock = new IO::Socket::INET(
        Proto => 'tcp', LocalPort => $main::svc_conf->{LOG_MON_PORT},
        Listen => 1, Reuse => 1);
    if (! $log_mon_sock) {
        warn "new IO::Socket::INET($main::svc_conf->{LOG_MON_PORT}) failed: $!";
        exit(0);
    }

    my $log_server = {};
       $log_server->{SUBDIR} = 'LOGMON';
       $log_server->{PORT} = $main::svc_conf->{LOG_MON_PORT};
       $log_server->{SOCK} = $log_mon_sock;
       $log_server->{MSGS} = [];
       $log_server->{STATUS} = 'LISTENING';

    $main::LOG_SERVERS->{$main::svc_conf->{LOG_MON_PORT}} = $log_server;
    $main::SOCK_SERVERS->{$log_mon_sock} = $log_server;

    $main::log_mon_server = $log_server;
  }

    for (my $i = 0; $i < @{$main::LOG_PORT}; $i++) {
        my $log_server = {};

        my ($SUBDIR, $PORT) = ('', '');

        if ($main::LOG_PORT->[$i] =~ /(\S+):(\d+)/) {
            ($SUBDIR, $PORT) = ($1, $2);
            $log_server->{SUBDIR} = $SUBDIR;
            $log_server->{PORT} = $PORT;
        } else {
            warn "Illegal LOG_PORT format: $main::LOG_PORT->[$i]" if $DEBUG;
            next;
        } # if

        ASSERT(defined $log_server->{PORT});

        my $socket = new SockUDP($PORT);

        $log_server->{SOCK} = $socket;
        if (! $log_server->{SOCK}) {
            die "new SockUDP($PORT) failed: $!";
        }

        warn "waiting port: $PORT, subdir: $log_server->{SUBDIR}" if $DEBUG;

        # warn "$log_server->{SOCK}: new SockUDP($PORT)" if $DEBUG;

        $log_server->{MSGS} = [];

        $main::LOG_SERVERS->{$PORT} = $log_server;

        # ¼ÒÄÏÀ» ¾Ë¾ÒÀ» ¶§, ÇØ´ç ·Î±×¼­¹ö¸¦ Ã£¾Æ³»±â À§ÇÑ ÇØ½¬
        $main::SOCK_SERVERS->{$socket} = $log_server;
    } # for

    # ¿©·¯ °³ÀÇ ¼ÒÄÏÀ» µ¿½Ã¿¡ read ÇÏ±â À§ÇÑ select±¸Á¶.
    $main::SELECT = new IO::Select();
    foreach my $socket (keys %{$main::SOCK_SERVERS}) {
        # warn "main::SELECT->add($socket)" if $DEBUG;
        $main::SELECT->add($socket);
    } # for

    # ¸ÞÀÎ ·çÇÁ ÁøÀÔ
    main_loop();
}

sub read_config($)
{
    my ($conf_file) = @_;

    ASSERT(defined $conf_file) if $DEBUG;
    ASSERT($conf_file ne "") if $DEBUG;

    my $conf = {};
    if (! -e $conf_file) {
        return $conf;
    }

    ASSERT(-e $conf_file) if $DEBUG;

    # $conf->{LOG_DIR} = "$ENV{KTMAIL_ROOT}/log";
    # $conf->{LOG_PORT} = [];
    # $conf->{LOG_MIRROR_IP} = {};

    local(*F);

    if (! open(F, "$conf_file")) {
        warn "open($conf_file) failed." if $DEBUG;
        return $conf;
    }


    my @lines = <F>;
    close(F);

    foreach my $line (@lines) {
        $line =~ s/\r?\n$//g; # chomp

        if ($line =~ /^LOG_DIR (\S+)/i) {
            my $log_dir = $1;
warn "LOG_DIR: $log_dir" if $DEBUG;
            $conf->{LOG_DIR} = $log_dir;
            next;
        }

        if ($line =~ /^LOG_PORT (.+)/i) {
            my @log_ports = split(/ /, $1);
            foreach my $log_port (@log_ports) {
                if ($log_port =~ /^(\S+):(\d+)$/) {
                    if (! defined($conf->{LOG_PORT})) {
                        $conf->{LOG_PORT} = [];
                    }
warn "LOG_PORT: $log_port" if $DEBUG;
                    push @{$conf->{LOG_PORT}}, $log_port;
                }
            }
            next;
        }

        if ($line =~ /^LOG_MIRROR (.+)/i) {
            my @log_mirrors = split(/ /, $1);
            foreach my $log_mirror (@log_mirrors) {
                if ($log_mirror =~ /^(\S+):(\S+)$/) {
                    my ($code, $ip) = ($1, $2);
                    if (! defined($conf->{LOG_MIRROR_IP})) {
                        $conf->{LOG_MIRROR_IP} = {};
                    }

warn "LOG_MIRROR $code:$ip";
                    $conf->{LOG_MIRROR_IP}->{$code} = $ip;
                }
            }
        }

        if ($line =~ /^(\S+)\s+(.+)$/) {
            $conf->{$1} = $2;
        }
    }

    return $conf;
}

MAIN:
{
    if (! @ARGV) {
        print "Usage: $0 -debug/-normal/-version [svc.conf]\n";
        print "          [log_dir=$main::LOG_DIR]\n";

        for (my $i = 0; $i < @{$main::LOG_PORT}; $i++) {
            print "          [log_port=$main::LOG_PORT->[$i]]\n";
        }

        print "          [flush_duration=$main::flush_duration]\n";

        print "\n";
        POSIX::_exit(0);
    } # if


    if ($ARGV[0] eq '-version') {
        print "VERSION: $main::VERSION\n";
        exit(0);
    }

    foreach my $arg (@ARGV) {
        $main::debug = 1 if ($arg =~ /^\-debug$/ || $arg =~ /^\-d$/);
        $main::debug = 0 if ($arg =~ /^\-normal$/ || $arg =~ /^\-n$/);
    }

    $DEBUG = $main::debug if ($main::debug);

    $main::conf_file = "/usr/local/mobigen/CrediMail/conf/dmail.conf";
    $main::conf_file = "$ENV{KTMAIL_ROOT}/conf/dmail.conf"
                          if (defined $ENV{KTMAIL_ROOT});


    foreach my $arg (@ARGV) {
        $main::conf_file = $arg if ($arg =~ /\.conf$/);
    }

    # ÆÄÀÏ·ÎºÎÅÍ ¼³Á¤°ªÀ» ÀÐ¾îµéÀÓ. µðÆúÆ®°ªº¸´Ù ¼³Á¤ÆÄÀÏÀÌ ´õ ³ôÀº ¿ì¼±¼øÀ§!
    my $conf = read_config($main::conf_file);

    $main::LOG_DIR = $conf->{LOG_DIR};
    $main::LOG_PORT = $conf->{LOG_PORT};


  {
    # 2004/01/12 ·Î±× ¼­¹ö ÀÚÃ¼¸¦ ¸ð´ÏÅÍ¸µ ÇÏ±â À§ÇØ¼­,
    #            ·Î±× ¼­¹ö ¸ð´ÏÅÍ¸µ ¿ë TCP Æ÷Æ®¸¦ ÇÏ³ª Á¤ÀÇÇÑ´Ù.
    $main::svc_conf = read_config("./svc.conf");

    if (defined $main::svc_conf->{LOG_DIR}) {
        $main::LOG_DIR = $main::svc_conf->{LOG_DIR};
    }

    if (defined $main::svc_conf->{LOG_PORT}) {
        $main::LOG_PORT = $main::svc_conf->{LOG_PORT};
    }

    if (defined $main::svc_conf->{FLUSH_DURATION}) {
        $main::flush_duration = $main::svc_conf->{FLUSH_DURATION};
    }

    $main::LOG_MIRROR_IP = $main::svc_conf->{LOG_MIRROR_IP};
  }

    # ÄÚ¸Çµå ¶óÀÎÀ¸·Î ÀÔ·ÂÇÑ °ÍÀÌ ¼³Á¤ÆÄÀÏ º¸´Ù ¿ì¼±¼øÀ§°¡ ³ôÀ½.
    my $LOG_PORT = [];
    foreach my $arg (@ARGV) {
        $main::flush_duration = $1 if ($arg =~ /flush_duration.(\d+)/);
        $main::LOG_DIR = $1 if ($arg =~ /log_dir.(\S+)/i);

        if ($arg =~ /log_port.(\S+:\d+)/i) {
            push @{$LOG_PORT}, $1;
        }
    } # foreach


    ASSERT(defined $main::LOG_DIR);

    # ÀÔ·ÂÀ¸·Î log_ports ÀÌ ÇÏ³ª¶óµµ µé¾î¿À¸é, ±âÁ¸ ·Î±× ITEMÀº ¸ðµÎ ¹«½Ã.
    if (@{$LOG_PORT} > 0) {
        $main::LOG_PORT = $LOG_PORT;
    }

    $SIG{CHLD} = \&REAPER;
    # µð¹ö±ë ¸ðµå
    if ($main::debug) {
        run_log_d();
        POSIX::_exit(0);
    } # if

    # µ¥¸ó ¸ðµå
    if (fork() == 0) {
        if (fork() == 0) {
            run_log_d();
        }
        POSIX::_exit(0);
        wait();
    }
    POSIX::_exit(0);
}

__END__
