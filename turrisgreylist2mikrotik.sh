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
PROJECT_DIR=$(dirname "$0")
MIKROTIK_LIST="${PROJECT_DIR}/turrisgreylist2mikrotik.rsc"
CURR_DATE=$(date "+%F")
DOWNLOAD_URL="https://view.sentinel.turris.cz/greylist-data/greylist-latest.csv"
CURL_EXITCODE=0
NEXT_TRY_SECS=60
TRIES=120
COUNTER=0

while [ "$CURL_EXITCODE" -ne 200 ] && [ $COUNTER -lt $TRIES ]
do
  CURL_EXITCODE=$(curl -s -o /dev/null -w "%{http_code}" "$DOWNLOAD_URL")
  curl -L -s "$DOWNLOAD_URL" | tail -n+2 > "$TURRIS_LIST"
# Give a chance to server for at least minute if exitcode is not 200
  if [ "$CURL_EXITCODE" -ne 200 ];then
    sleep "$NEXT_TRY_SECS"
  fi
  COUNTER=$((COUNTER+1))
done

if [ $COUNTER -eq $TRIES ] && [ "$CURL_EXITCODE" -ne 200 ];then
  echo "DOWNLOAD FAILED AFTER $TRIES TRIES"
  exit 1
fi

awk -v curr_date="$CURR_DATE" -F "," 'BEGIN { print "#List downloaded at "curr_date
             print "/log info \"Loading turris_greylist address list\""
             print "/ip firewall address-list remove [/ip firewall address-list find list=turris_greylist]"
             print "/ip firewall address-list"}
           { print ":do { add address=" $1 " list=turris_greylist timeout=60d } on-error={} "}' "$TURRIS_LIST" > "$MIKROTIK_LIST"

#CLEANUP
rm "$TURRIS_LIST"
