#!/bin/env perl
# ---------------------------------------------------
# Author: nomota@mobigen.com, hiongun@gmail.com
# ---------------------------------------------------
use strict;

use POSIX;
use Carp;
use SockUDP;
use IO::Socket::INET;
use IO::Select;
use Tie::RefHash;
# use VERSION;
require 'flush.pl';

$main::flush_duration = 1;
$main::debug = 0;

$main::LOG_DIR = "/tmp/LOG";

$main::LOG_PORT = [];
$main::LOG_PORT->[0] = "TEST:52526";

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

    # Data Structure for a specific server (for a specific UDP port)
    # 
    # $log_server = {
    #     SUBDIR => 'TEST',
    #     PORT => 52526,
    #     SOCK => $SockUDP,
    #     FH => open_log_file_handle,
    #     MSGS => [$msg1, $msg2, $msg3, ...] # messages yet to be flushed
    # }
    #
    # $msg = [$host, $ip, $msg_string]
    #

    ASSERT(defined $log_server);
    ASSERT(defined $log_server->{SUBDIR}); # SHIELD_LOG
    ASSERT(defined $log_server->{PORT});   # 52526
    ASSERT(defined $log_server->{MSGS});   # [[$ip,$port,$msg], ...]
    ASSERT(@{$log_server->{MSGS}} > 0);

    # =======================================
    # if LOG dir doesn't exists, create one.
    # =======================================
    ASSERT(defined $main::LOG_DIR);   # /usr/local/mobigen/CrediShield/logs
    my $log_path = "$main::LOG_DIR/$log_server->{SUBDIR}";

    $main::cur_time = time();

    # -------------------------------
    # Create directory for each day
    # -------------------------------
    #                           YYYYmmdd
    my $today = POSIX::strftime("%Y%m%d", localtime($main::cur_time));

    # ---------------------------------------
    # Create log file for each hour
    # ---------------------------------------
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

        # if there exists the log file, but not open
        # -- perhaps the daemon has been dead. Need to open it again

        my $fh = new_fh();
        $log_server->{FH} = $fh;
        umask(0000);
        open($fh, ">> $log_path/$today/$cur_hour");
    }

    # --------------------------------------------------
    # if it's open, we can write/append log data
    # --------------------------------------------------

    ASSERT(defined $log_server->{FH});

    my $fh = $log_server->{FH};

    foreach my $msg (@{$log_server->{MSGS}}) {
        # $msg->[0] IP Address
        # $msg->[1] Port Number (UDP)
        # $msg->[2] Log Message (text)

        # print F "$msg->[0] $msg->[2]";

        warn "$readable_time $msg->[2]" if $DEBUG;

        print $fh "$readable_time $msg->[2]";

        if (substr($msg->[2], -1) ne "\n") {
            print $fh "\n";
        }
    }

    $log_server->{MSGS} = [];

    flush($fh); # Check performance issue
}

sub handle_read($)
{
    my ($log_server) = @_; # a UDP server, that is ready for the port
                           # to which a message just arrived

    # $log_server = {
    #     SUBDIR => 'TEST',
    #     PORT => 52526,
    #     SOCK => $SockUDP,
    #     MSGS => [$msg1, $msg2, $msg3, ...] # messages to be flushed
    # }

    my $udp_sock = $log_server->{SOCK};

    my ($host, $port, $msg) = $udp_sock->recv(); # read msg from the UDP socket

    if (! defined $msg) {
        warn "recv() fail." if $DEBUG;
        return;
    }

    warn "[$host, $port, $msg]" if $DEBUG;

    # --------------------------------------
    # just append the message to the buffer
    # --------------------------------------
    push @{$log_server->{MSGS}}, [$host, $port, $msg];

    # --------------------------------------
    # 2010.10.02 nomota LOG_MIRROR added
    # --------------------------------------
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

    # -------------------------------------------
    # a typical multi-port handling routine
    # -------------------------------------------

    my $last_flushtime = time(); # remembers time of the last flush

    while (1) {
        $main::cur_time = time();

        ### WAIT ################################

        warn "inner loop, select()";
        my @ready_socks = $main::SELECT->can_read(1.0);

        ### READ ################################

        foreach my $udp_sock (@ready_socks) {
            # --------------------------------------------
            # read messages from readable sockets
            # append them to the MSGS buffer for each port
            # --------------------------------------------
            my $log_server = $main::SOCK_SERVERS->{$udp_sock};

            ASSERT(defined $log_server);

            # --------------------------------------------
            # check if it's the monitoring port
            # --------------------------------------------
            if ($log_server == $main::log_mon_server) {
                warn "handle_mon_read()";
                handle_mon_read($log_server);
            } else {
                warn "handle_read()";
                handle_read($log_server);
            }
        } # foreach

        ### WRITE ###############################

        # ----------------------------------------------------------
        # flush messages in MSGS buffer, periodically
        # ----------------------------------------------------------
        if (($main::cur_time - $last_flushtime) >= $main::flush_duration) {
            # ----------------------------------------------
            # flush log data into directory for each port
            # ----------------------------------------------

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
    # --------------------------------------------------------------
    # Internal Data Structure:
    #
    # multiple log searvers are listening UPD ports independantly
    # with separate buffer space, each server is dedicated to each UDP port
    # --------------------------------------------------------------
    # $main::LOG_SERVERS = { $port => $log_server, $port => $log_server, ... }
    #
    # $port => {
    #     SUBDIR => 'TEST',
    #     PORT => 52526,
    #     SOCK => $SockUDP,
    #     MSGS => [$msg1, $msg2, $msg3, ...] # messages to be flushed
    # }
    #
    # Hash structure to lookup the socket->log_server data structure
    #
    # $main::SOCK_SERVERS = { $sock => $log_server, $sock => $log_server, ... }
    # ----------------------------------------------------------------------

    warn "FLUSH_DURATION: $main::flush_duration" if $DEBUG;

    ASSERT(defined($main::LOG_PORT));

    $main::LOG_SERVERS = {}; # container of log servers

    # ---------------------------------------------------------------
    # To make $socket reference as a key (non string/integer key)
    # Tie::RefHash is necessary.
    # ---------------------------------------------------------------
    my %sock_servers = ();
    tie %sock_servers, 'Tie::RefHash';
    $main::SOCK_SERVERS = \%sock_servers;

  {
    # --------------------------------------------------
    # 2004/01/12 Need to monitor the logd itself 
    #     listens a TCP port (monitoring port)
    # --------------------------------------------------
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

        # -------------------------------
        # Quick reverse lookup hash
        # -------------------------------
        $main::SOCK_SERVERS->{$socket} = $log_server;
    } # for

    # --------------------------------------------------------------
    # select for simultaneous accepting data among multiple ports
    # --------------------------------------------------------------
    $main::SELECT = new IO::Select();
    foreach my $socket (keys %{$main::SOCK_SERVERS}) {
        # warn "main::SELECT->add($socket)" if $DEBUG;
        $main::SELECT->add($socket);
    } # for

    # The main loop
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

    $main::LOG_DIR = "/tmp/LOG";
    $main::LOG_PORT = "9998";

    $DEBUG = $main::debug if ($main::debug);

    my $conf_file = "./svc.conf";
    foreach my $arg (@ARGV) {
        $conf_file = $arg if ($arg =~ /\.conf$/);
    }

    $main::svc_conf = read_config($conf_file);

  {
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

    my $LOG_PORT = [];
    foreach my $arg (@ARGV) {
        $main::flush_duration = $1 if ($arg =~ /flush_duration.(\d+)/);
        $main::LOG_DIR = $1 if ($arg =~ /log_dir.(\S+)/i);

        if ($arg =~ /log_port.(\S+:\d+)/i) {
            push @{$LOG_PORT}, $1;
        }
    } # foreach


    ASSERT(defined $main::LOG_DIR);

    if (@{$LOG_PORT} > 0) {
        $main::LOG_PORT = $LOG_PORT;
    }

    # if it's in debug mode don't run as a daemon
    if ($main::debug) {
        run_log_d();
        POSIX::_exit(0);
    } # if

    # double fork to make it run as daemon
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
