#!/bin/bash

## options ##

bot_nick="zombie_detector"
channels="#zdtest"
query_interval=30 #seconds
if false; then read -sp "Channel key: " chankey; fi
# ^ change that to false to turn off prompting for chankey

## utility functions ##

debug() {
    # utility for echoing to stderr
    echo "$*" 1>&2
}

raw() {
    # utility for sending server commands
    debug "--> $*"
    echo "$*" >> .botfile
}


## special mode that just executes the names-checking loop ##
if [ "$1" = "names_only" ]; then
    raw "NAMES $channels"
    sleep $query_interval
    exec $0 names_only
    # this line won't normally be reached, but it's here in case the exec fails
    exit
fi


## bot setup ##

first_run=true
mkfifo .botfile
chmod 600 .botfile


## main bot loop ##

tail -f .botfile | ncat --ssl irc.cat.pdx.edu 6697 | while true; do
    if $first_run; then
        debug "starting setup"
        # set nick and get in channels
        raw "NICK $bot_nick"
        raw "USER $bot_nick 0 $bot_nick :Zombie Detector"
        raw "JOIN $channels $chankey"
        # start the name loop
        $0 names_only &
        loop_pid=$!
        #trap "raw QUIT" hup int term quit
        first_run=false
    fi
    read server_line
    server_line=$(echo "$server_line" | tr -d "\n\r")
    debug "<-- |$server_line|"
    if echo "$server_line" | grep -qi "^PING"; then
        debug "ping ..."
        # reply to pings so we don't time out
        raw $(echo "$server_line" | sed "s/PING/PONG/i")
    elif echo "$server_line" | grep -qi "^:relsqui!.*:$bot_nick: quit$"; then
        debug "told to quit; quitting"
        raw "QUIT :Leaving ..."
        kill $loop_pid
        sleep 1
        rm .botfile
        debug "breaking ..."
        break
    elif echo "$server_line" | grep -qi "^:[^ ]+ 353 $bot_nick"; then
        # this is a names reply, make a note of it
        channel="$(echo "$server_line" | sed "s/[^#]*\(\#[^ ]*\).*/\1/")"
        users="$(echo "$server_line" | sed "s/.[^:]*:\(.*\)/\1/")"
        #debug "$(date "+%F %T") $channel: $users"
        debug "$channel: $users"
    fi
done
