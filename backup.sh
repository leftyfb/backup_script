#!/bin/bash
#
#### Dependencies: ######
## rsync - for backing up files
## mysql - if you want to backup mysql db's
## bc - calculations

### NOTE: ####
## Backing up over SSH assumes you have a profile for the target setup in your ~/.ssh/config file.

# ------------------ begin config --------------------------

recipient=email@example.com
smtp_login=email@example.com

# Local directory where we'll be doing work and keeping copies of all archived files
storage="/media/backups"

backupdir="$storage/$target"

# Backup log file
logfile="$backupdir/backup.log"

# MySQL username and password and db's
DEFAULT_MYSQLUSER="mysqluser"
DEFAULT_MYSQLPASS="yourpasswordhere"

# excludes
excludesdir="/root"
includedir="/root"
excvar="backup_excludes.var"
excusr="backup_excludes.usr"
exchome="backup_excludes.$target"

emailfooter="$0 - $(date) - $HOSTNAME"
lastbackup=$(grep " $target " $storage/backup_log 2>/dev/null|tail -n1)

# ---------------------  end config ---------------------- 

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --target=<name>      Specify the backup target.
  --local              Run the script in local mode.
  --mysqluser=<user>   Override the default MySQL username.
  --mysqlpass=<pass>   Specify the MySQL password.
  --help               Display this help message.

Examples:
  $0 --target=production
  $0 --local
  $0 --mysqluser=admin
  $0 --mysqluser=admin --mysqlpass=supersecure
  $0 --target=staging --local --mysqluser=admin --mysqlpass=topsecret
EOF
  exit 1
}

if [[ $# -eq 0 ]]; then
  echo "Error: No arguments provided."
  usage
fi

for arg in "$@"; do
  case $arg in
    --target=*)
      target="${arg#*=}"
      shift
      ;;
    --local=*)
      local=true
      shift
      ;;
    --mysqluser=*)
      MYSQLUSER="${arg#*=}"
      USER_SPECIFIED=true
      shift
      ;;
    --mysqlpass=*)
      MYSQLPASS="${arg#*=}"
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown argument: $arg"
      usage
      ;;
  esac
done


MYSQLUSER="${MYSQLUSER:-$DEFAULT_MYSQLUSER}"
MYSQLPASS="${MYSQLPASS:-$DEFAULT_MYSQLPASS}"

# check if storage is mounted
if ! mount | grep -q "$storage"; then
  echo "Error: ${storage} not mounted. Exiting..."
  exit 1
fi

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

# check for backup media
if [ ! -d $backupdir ];
then
 line1="NO BACKUP MEDIA LOCATED!"
 line2="HALTING BACKUP!"
 line3="Last Backup: $(echo $lastbackup)"
 echo "NO BACKUP MEDIA LOCATED!\nHALTING BACKUP!"
 echo -e "$line1\n$line2\n\n$line3\n\n$emailfooter"|mail -s "$HOSTNAME [BACKUP FAILED!] $target for $(date +%m-%d-%y)" $recipient
   exit 0
else
   cd $backupdir
fi

# check if doing backup over ssh or locally
if [[ "$local" == true ]]; then
	echo "Running backup locally"
	via=""
else
	echo "Running backup over ssh"
	via="-e 'ssh -o StrictHostKeyChecking=no' $target:"
	# check for remote target
	if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" true 2>/dev/null; then
		echo "SSH Connection established to $target"
	else
		echo -e "Hostname $target not accessible!\nHALTING BACKUP!"
		line1="Hostname $target not accessible!"
		line2="HALTING BACKUP!"
		line3="Last Backup: $(echo $lastbackup)"
		echo -e "$line1\n$line2\n\n$line3\n\n\n$emailfooter"|mail -s "$HOSTNAME [BACKUP FAILED!] $target for $(date +%m-%d-%y)" $recipient
		exit 0
	fi
fi

# make backup directories.
current="$backupdir/current"
old="$backupdir/old"
now="$old/$today"

checkDir $current
checkDir $old
checkDir $now


# get list of home directories
if [[ "$local" == true ]]; then
   homelist=$(ls /home)
else
   homelist=$(ssh $target "ls /home/")
fi

# Ugly converting of transferred file sizes from human to machine then back again to get total output in the end
convert2machine () {
KILO=1000
MEGA=`echo "$KILO ^ 2" |bc`
GIGA=`echo "$KILO ^ 3" |bc`
declare -a values
n=1

for i in `grep "Total trans" $logfile|awk  '{print $5}'|grep -v ^0|sed 's/,//g'`
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
  eval rsync -aphv --delete --stats --progress --exclude-from="$exch" $via/home/$i/ $current/home/$i
  echo 
done
eval rsync -dvp -delete --stats --progress $via/home/ $current/home/

## root
echo "== backing up /root/ =="
checkDir $current/root/
eval rsync -aphv --delete --stats --progress $via/root/ $current/root/

## etc
echo "== backing up /etc/ =="
checkDir $current/etc/
eval rsync -aphv --delete --stats --progress $via/etc/ $current/etc/

## var
echo "== backing up /var/ =="
checkDir $current/var/
eval rsync -aphv --delete --delete-excluded --progress --exclude-from="$excv" --stats $via/var/ $current/var/

## usr
echo "== backing up /usr/ =="
checkDir $current/usr/
eval rsync -aphv --delete --delete-excluded --progress --exclude-from="$excu" --stats $via/usr/ $current/usr/

## check for include file
if [ -f $includedir/backup_includes.$target ] ; then
  echo "==== backing up includes ===="
  eval rsync -aphv --delete --stats --progress --include-from="$includedir/backup_includes.$target" --exclude="/*" ${via}/ ${current}/
fi

## Backup MYSQL databases
# get list of databases to backup

if $(ssh $target "command -v mysql" &>/dev/null) ; then
	checkDir $now/dbs
	echo "=== backing up Databases... ==="
	if [[ "$USER_SPECIFIED" == true ]]; then
		DBS=$(ssh $target "mysql -u $MYSQLUSER -Bse 'show databases'")
		for m in $DBS;do echo "backing up $m...";ssh $target mysqldump --single-transaction -u $MYSQLUSER $m | gzip > $now/dbs/$m.sql.gz;done
	else
		DBS=$(ssh $target "mysql -u $MYSQLUSER --password=$MYSQLPASS -Bse 'show databases'")
		for m in $DBS;do echo "backing up $m...";ssh $target mysqldump --single-transaction -u $MYSQLUSER --password=$MYSQLPASS $m | gzip > $now/dbs/$m.sql.gz;done
	fi
else
	echo "=== No Databases found ==="
fi

ssh $target "echo $(date +%y%m%d) > /root/.lastbackup"

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
  daycount=$(find ${old}/${i%/*} -maxdepth 1 -mindepth 1 -type d|wc -l)
  if [ $daycount = 0 ] ; then
   rmdir ${old}/${i%/*}
   echo "deleted ${i%/*}"
  fi
fi
}

cleanMonth() {
for i in $(last90days) 
 do
  monthcount=$(ls $old/$(echo $i|awk -F "/" '{print $1"/"$2}')/ 2>/dev/null |wc -l)
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
  yearcount=$(find $old/${i%%/*} -maxdepth 2 -mindepth 2 -type d 2>/dev/null|wc -l)
  if [ $i = "$lastYear/01/01" ] || [ $i = "$lastYear/01/02" ]; then
   continue
  elif [ $yearcount = 1 ]; then
   continue
  else
   ifdirdel $old/$i
  fi
done
}

cleanMonth
if [ -d $old/$lastYear ];
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
echo -e "$line1\n\n$line2\n$line3\n$line4\n$line5\n\n$line6\n\n$line7\n\n$emailfooter"|mail -s "$HOSTNAME [BACKUP OK] $target for $(date +%m-%d-%y)" $recipient

echo -e "$edate $target $(echo $total)M $hours:$minutes:$seconds " >> $storage/backup_log
echo "done"

cp $logfile $now/
