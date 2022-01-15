#!/bin/bash

####
#Mikrotik Usage
#--------------
#Add MIKROTIK SCRIPT lines below into mikrotik script
#Set Scheduler to script
#Profit
###

#/tool fetch url=https://raw.githubusercontent.com/pschonmann/turrisgreylist2mikrotik/master/turrisgreylist2mikrotik.rsc
#/import file-name=turrisgreylist2mikrotik.rsc

TURRIS_LIST=$(mktemp)
PROJECT_DIR=$(dirname $0)
MIKROTIK_LIST=${PROJECT_DIR}/turrisgreylist2mikrotik.rsc

curl -s https://project.turris.cz/greylist-data/greylist-latest.csv | tail -n+2 > $TURRIS_LIST

awk -F "," 'BEGIN { print "/log info \"Loading turris_greylist address list\""
             print "/ip firewall address-list remove [/ip firewall address-list find list=turris_greylist]"
             print "/ip firewall address-list"}
           { print ":do { add address=" $1 " list=turris_greylist } on-error={} "}' $TURRIS_LIST > $MIKROTIK_LIST

#CLEANUP
rm $TURRIS_LIST
