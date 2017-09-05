#!/bin/sh

ps -ef|grep logd.pl|grep -v grep|awk '{print $2}'|xargs kill -9 >/dev/null 2>/dev/null

