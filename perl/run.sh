#!/bin/sh

./stop.sh

perl ./logd.pl -normal flush_duration=5 ./svc.conf >/dev/null 2> /dev/null&

