#!/bin/bash

TURRIS_LIST=$(mktemp)
MIKROTIK_LIST=./turrisgreylist2mikrotik.rsc

curl -s https://project.turris.cz/greylist-data/greylist-latest.csv | tail -n+2 > $TURRIS_LIST

awk -F "," 'BEGIN { print "/log info \"Loading turris_greylist address list\""
             print "/ip firewall address-list remove [/ip firewall address-list find list=turris_greylist]"
             print "/ip firewall address-list"}
           { print ":do { add address=" $1 " list=turris_greylist } on-error={} "}' $TURRIS_LIST > $MIKROTIK_LIST

#CLEANUP
rm $TURRIS_LIST
