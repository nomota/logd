logd - A versatile log daemon
=============================


A versatile log daemon for Linux system software. (in three languages - Perl, Python, Java)

Here's the requirements for the log daemon.

(1) Easy to use.
(2) Accepts logs from difference source in a linux/unix box.
(3) Replication accross the servers.
(4) UDP-based, so that no lock problem occurs.
(5) Can be monitored remotely, via a TCP port.
(6) Configurable in a very simple configuration file. 
(7) Language independent. (accepts logs from S/Ws in different languages)
(8) Automatic log rotation.

Why not Log4J or python logging.Logger?
=======================================

If you are building a very large and complex system in Linux/Unix system, you are going to 
need some centralized daemon that accepts log messages from various softwares written in
different languages. Log4J or python logging library are not enough because of language
barriers.

The goal of this project is to give a generalized, versatile tool for system developers
so that they can centralize the log data in syslogd style, but in easier way - easier
to configure, easier to extend.

What's logd?
============

Logd is a daemon process that is accepting log messages from multiple UDP ports at the
same time. Each UDP port represents different log source, and we can specify as many 
log sources as possible.

Logd writes data into ~/$CODE/YYYYmmdd/HH files, where $CODE represents the source of
the log.


How to use logd?
================

First download the logd-versi-o-n.tar.gz and untar/ungzip - results files in ./logd/
In ./logd/ dir there are two scripts ./run.sh and ./stop.sh - you can start and stop
the daemon by using those scripts.

To configure, you need to edit ./svc.conf file. 

