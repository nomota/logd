#!/bin/sh

ps -ef|grep logd.pl|grep -v grep|xargs kill -9
