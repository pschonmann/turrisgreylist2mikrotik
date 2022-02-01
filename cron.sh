#!/bin/bash

#Regular updates and update to git

#https://project.turris.cz/greylist-data/
#Assume list is prepared before Monday 2:00AM

#0 2 * * 1 /path/to/git/turrisgreylist2mikrotik/turrisgreylist2mikrotik.sh &>>/path/to/turrisgrelist2mikrotik.log
#5 2 * * 1 /path/to/git/turrisgreylist2mikrotik/cron.sh &>> /path/to/git/turrisgreylist2mikrotik/cron.log 


LOGDIR=$(dirname $0)
LOGFILE=$0.log
GIT=`which git`

echo "----- STARTED $0 `date +%F-%H-%M-%S` -----" >> $LOGFILE

#SOME DEBUG SHIT if you need
#env >> $LOGFILE

cd $LOGDIR 

$GIT add turrisgreylist2mikrotik.rsc &>>$LOGFILE
$GIT commit -m "Commit `date +%F`" &>>$LOGFILE
$GIT push &>>$LOGFILE
echo "----- FINISHED $0 `date +%F-%H-%M-%S` -----" >> $LOGFILE
