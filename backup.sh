#!/bin/bash
#
#### usage: ####
###  backup.sh <hostname> local

#### Dependencies: ######
## rsync - for backing up files
## mysql - if you want to backup mysql db's

### NOTE: ####
## To backup locally without ssh, type local after the hostname.
## To use ssh keys, setup your ~/.ssh/config for the hostname.
# ------------------ begin config --------------------------

recipient=leftyfb@left-click.org
smtp_login=leftyfb@left-click.org

bastion=bastionserver01

# Local directory where we'll be doing work and keeping copies of all archived files
storage="/media/backups"
backupdir="$storage/$1"

# Backup log file
logfile="$backupdir/backup.log"

# The user and the address of machine to be backed up via ssh
login="$1"

# The number of days after which old backups will be deleted
days="120"					

# MySQL username and password and db's
MYSQLUSER="mysqluser"
MYSQLPASS="yourpasswordhere"

# excludes
excludesdir="/root"
excvar="backup_excludes.var"
excusr="backup_excludes.usr"
exchome="backup_excludes.$1"

emailfooter="$0 - $(date) - $HOSTNAME"
lastbackup=$(grep " $1 " $storage/backup_log|tail -n1)

# ---------------------  end config ---------------------- 
checkDir()
{
	if [ ! -d "$1" ]
	then
		mkdir -p "$1"
	fi
}
checkDir $backupdir

exec > $logfile 2>&1

## check for var excludes file
if [ -f $excludesdir/$excvar ];
then
   excv="$excludesdir/$excvar"
else
   excv="/dev/null"
fi

## check for usr excludes file
if [ -f $excludesdir/$excusr ];
then
   excu="$excludesdir/$excusr"
else
   excu="/dev/null"
fi

## check for home excludes file
if [ -f $excludesdir/$exchome ];
then
   exch="$excludesdir/$exchome"
else
   exch="/dev/null"
fi


# Prints date of the format YYYY/MM/DD
year=$(date +%Y)
month=$(date +%m)
day=$(date +%d)
today="$year/$month/$day"

# get list of databases to backup
DBS=$(ssh $login "mysql -u $MYSQLUSER --password=$MYSQLPASS -Bse 'show databases'")

# check if doing backup over ssh or ssh through bastion or locally
if [ "$2" = "local" ]; then
   via=""
elif [ "$2" = "bastion" ]; then
   via="-e \"ssh $bastion ssh\" $login:" ; ssh=1
else
   via="-e 'ssh -o StrictHostKeyChecking=no' $login:" ; ssh=1
fi

# check for backup media
if [ ! -d $backupdir ];
then
 line1="NO BACKUP MEDIA LOCATED!"
 line2="HALTING BACKUP!"
 line3="Last Backup: $(echo $lastbackup)"
 echo "NO BACKUP MEDIA LOCATED!\nHALTING BACKUP!"
 echo -e "$line1\n$line2\n\n$line3\n\n$emailfooter"|mail -s "[BACKUP FAILED!] $1 for $(date +%m-%d-%y)" $recipient
   exit 0
else
   cd $backupdir
fi

# check for remote machine
if [[ $via != "" && $2 != bastion ]]; then
	up=`ssh -q $1 echo "1"`
elif [[ $via != "" && $2 = bastion ]]; then 
	up=`ssh -q $bastion ssh -q $1 echo "1"`
else
	up="1"
fi

if [[ $ssh = "1" && $up != 1 ]]; then
 echo -e "Hostname $1 not accessible!\nHALTING BACKUP!"
 line1="Hostname $1 not accessible!"
 line2="HALTING BACKUP!"
 line3="Last Backup: $(echo $lastbackup)"
 echo -e "$line1\n$line2\n\n$line3\n\n\n$emailfooter"|mail -s "[BACKUP FAILED!] $1 for $(date +%m-%d-%y)" $recipient
   exit 0
else
echo "SSH Connection established to $1"
fi

# make backup directories.
current="$backupdir/current"
old="$backupdir/old"
now="$old/$today"

checkDir $current
checkDir $old
checkDir $now


# get list of home directories
if [ "$2" = "local" ]; then
   homelist=$(ls /home)
elif [ "$2" = "bastion" ]; then
   homelist=$(ssh $bastion ssh $login "ls /home/")
else
   homelist=$(ssh $login "ls /home/")
fi

# Ugly converting of transferred file sizes from human to machine then back again to get total output in the end
convert2machine () {
KILO=1000
MEGA=`echo "$KILO ^ 2" |bc`
GIGA=`echo "$KILO ^ 3" |bc`
declare -a values
n=1

for i in `grep "Total trans" $logfile|awk  '{print $5}'|grep -v ^0`
do
        if [ `echo $i | grep K` ]
        then
                num=`echo $i | sed -e "s/K//"`
                values[$n]=$(echo "$num * $KILO" | bc)
                (( n++ ))
        elif [ `echo $i | grep M` ]
        then
                num=`echo $i | sed -e "s/M//"`
                values[$n]=$(echo "$num * $MEGA" | bc)
                (( n++ ))
        elif [ `echo $i | grep G` ]
        then
                num=`echo $i | sed -e "s/G//"`
                values[$n]=$(echo "$num * $GIGA" | bc)
                (( n++ ))
        else
                values[$n]=$i
                (( n++ ))
        fi
done

arrn=1
sum=0

while [ $arrn -lt $n ]
do
        sum=$(echo "$sum + ${values[$arrn]}" | bc)
        (( arrn++ ))
done
}

convert2human () {
value=$(echo "$sum"|awk -F "." '{print $1}')
((kilo=value/1024))
((total=kilo/1024))
}

echo "**********************"
echo " Backup started at "
date
echo "**********************"
sdate=$(date)

## HOME      
echo "== backing up /home =="
for i in $homelist
 do
  echo "==== backing up $i ===="
  checkDir $current/home/$i
  eval rsync -aphvz --delete --stats --progress --compress --exclude-from="$exch" $via/home/$i/ $current/home/$i
  echo 
done
eval rsync -dvpz --delete --stats --compress --progress $via/home/ $current/home/

## root
echo "== backing up /root/ =="
checkDir $current/root/
eval rsync -aphvz --delete --stats --compress --progress $via/root/ $current/root/

## etc
echo "== backing up /etc/ =="
checkDir $current/etc/
eval rsync -aphvz --delete --stats --compress --progress $via/etc/ $current/etc/

## var
echo "== backing up /var/ =="
checkDir $current/var/
eval rsync -aphvz --delete --delete-excluded --progress --exclude-from="$excv" --stats --compress $via/var/ $current/var/

## usr
echo "== backing up /usr/ =="
checkDir $current/usr/
eval rsync -aphvz --delete --delete-excluded --progress --exclude-from="$excu" --stats --compress $via/usr/ $current/usr/

## Backup MYSQL databases
checkDir $now/dbs
echo "=== backing up Databases... ==="
for i in $DBS;do echo "backing up $i...";ssh $login mysqldump -u $MYSQLUSER --password=$MYSQLPASS $i | gzip > $now/dbs/$i.sql.gz;done

ssh $i "echo $(date +%y%m%d) > /root/.lastbackup"

# Update the mtime to reflect the snapshot time
echo "Updating mtime to reflect the snapshot time..."
touch $backupdir/current

# Make hardlink copy
echo "Making hardlink copy $now/ ...."
cp -al $current/* $now

# Remove old backups
#The past 7 days
day1=$(date  +%Y/%m/%d --date="1 days ago")
day2=$(date  +%Y/%m/%d --date="2 days ago")
day3=$(date  +%Y/%m/%d --date="3 days ago")
day4=$(date  +%Y/%m/%d --date="4 days ago")
day5=$(date  +%Y/%m/%d --date="5 days ago")
day6=$(date  +%Y/%m/%d --date="6 days ago")
day7=$(date  +%Y/%m/%d --date="7 days ago")
# past 4 Mondays
Monday1=$(date -d'monday-7 days' +%Y/%m/%d)
Monday2=$(date -d'monday-14 days' +%Y/%m/%d)
Monday3=$(date -d'monday-21 days' +%Y/%m/%d)
Monday4=$(date -d'monday-28 days' +%Y/%m/%d)
# past 4 Tuesdays
Tuesday1=$(date -d'tuesday-7 days' +%Y/%m/%d)
Tuesday2=$(date -d'tuesday-14 days' +%Y/%m/%d)
Tuesday3=$(date -d'tuesday-21 days' +%Y/%m/%d)
Tuesday4=$(date -d'tuesday-28 days' +%Y/%m/%d)
# 
lastYear=$(date +"%Y" -d last-year)

last90days() {
for i in `seq 1 90`
 do
  echo -e "$(date +%Y/%m/%d --date="$i days ago")"
done
}

aYearAgo() {
for i in `seq 365 730`
 do
  echo -e "$(date +%Y/%m/%d --date="$i days ago")"
done
}

ifdirdel() {
if [ -d $1 ]
 then
  rm -rf $1
  echo "deleted $1"
 else
  continue
fi
}

cleanMonth() {
for i in $(last90days) 
 do
  monthcount=$(ls $old/$(echo $i|awk -F "/" '{print $1"/"$2}')/|wc -l)
  if [ $i = "$day1" ] || [ $i = "$day2" ] || [ $i = "$day3" ] || [ $i = "$day4" ] || [ $i = "$day5" ] || [ $i = "$day6" ] || [ $i = "$day7" ]; then
   continue
  elif [[ $i == *01 ]] || [[ $i == *02 ]];
   then
    continue
  elif [ $i = "$Monday1" ] || [ $i = "$Monday2" ] || [ $i = "$Monday3" ] || [ $i = "$Monday4" ];
   then
    continue
  elif [ $i = "$Tuesday1" ] || [ $i = "$Tuesday2" ] || [ $i = "$Tuesday3" ] || [ $i = "$Tuesday4" ];
   then
    continue
  elif [ $monthcount = 1 ];
   then
    continue
  else
   ifdirdel $old/$i
  fi
done
}

cleanYear() {
for i in $(aYearAgo)
 do
  yearcount=$(ls -d $old/$lastYear/*/*|sort -u|grep -v ^$/|wc -l)
  if [ $i = "$lastYear/01/01" ] || [ $i = "$lastYear/01/02" ];
   then
   continue
  elif [ $yearcount = 1 ];
   then
    continue
  else
   ifdirdel $old/$i
  fi
done
}

cleanMonth
if [ -d $lastYear ];
 then
  cleanYear
fi

echo "**********************"
echo " Backup ended at "
date
echo "**********************"
edate=$(date)

seconds=$SECONDS
hours=$((seconds / 3600))
seconds=$((seconds % 3600))
minutes=$((seconds / 60))
seconds=$((seconds % 60))

#get human readable total
convert2machine
convert2human


echo "$(echo $total)M backed up"

echo "Sending mail..."
line1=$(echo "$(echo $total)M Backed up")
line2=$(echo -e "Backup started:\t$sdate")
line3=$(echo -e "Backup ended:\t$edate")
line4=$(echo -e "Backup took: $hours hour(s) $minutes minute(s) $seconds second(s) to run")
line5=$(echo -e "Last Backup: $lastbackup")
line6=$(egrep "backing up|Number of files t|Total transferred file size" $logfile|grep -v -- ": 0")
line7=$(grep -e "deleted $old" $logfile)
echo -e "$line1\n\n$line2\n$line3\n$line4\n$line5\n\n$line6\n\n$line7\n\n$emailfooter"|mail -s "[BACKUP OK] $1 for $(date +%m-%d-%y)" $recipient

echo -e "$edate $1 $(echo $total)M $hours:$minutes:$seconds " >> $storage/backup_log
echo "done"

cp $logfile $now/
