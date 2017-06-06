#!/bin/sh

ps -ef|grep logd.pl|grep -v grep|xargs kill -9 >/dev/null 2>/dev/null

