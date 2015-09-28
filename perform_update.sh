#!/bin/bash -e

# This script is intended to be used on Ubuntu based systems that are using LVM.
# Expectations are that you are using LVM snapshots BEFORE you perform any major system updates or software installs
# where you think your system may be rendered unbootable afterward. This script should help you by way of:
#	1. Taking a backup of /boot
#	2. Taking a backup of your home folder
#	3. sudo apt-get upgrade -d to only download the updates
#	4. Create a snapshot of your primary logical volume
#	5. Perform the sudo apt-get upgrade
#
# Author David Castellani	- github.com/davidcastellani
# Author Jeff Palmer		- github.com/palmerit

# cache sudo credentials
sudo -v

# Change this to your username, needs to coincide with your backup server username as well.
user=$USER

# This should be the hostname or IP address of the backup server where you will
# send your /boot and home folder
backupserver=172.16.1.4

# This setting restricts how much bandwidtht he backup process can use.
# 2500 should work out to about 25Mb/s
bwlimit=2500

# Define your boot device, this is needed to take a backup of /boot
# By default, it will look in /proc/mounts for a /boot device using an ext[2|3|4] filesystem.
# If this should fail for some reason, you can manually define it here, as an example:
#boot=/dev/sdb1
boot=`grep boot /proc/mounts | grep ext | cut -f 1 -d ' '`

# How big do you want your snapshot volume? Below is 15 GiB
snapsize=15G

# What is the path to your primary lv where all of your data is?
primarylv=/dev/mapper/vgsnap-lvroot

# Define the date
date=$(date "+%Y-%m-%dT%H_%M_%S")

# Home folder location using the $user variable
HOME=/home/$user

# Backup of /boot to a folder in your home folder, which will then be included
# in your home folder backup.
echo "#"
echo "# Taking backup of $boot with dd to $HOME/boot-backup-$date"
echo "#"
sudo dd if=$boot of=$HOME/boot-backup-$date
echo "#"
echo "# Changing ownership of $HOME/boot-backup-$date to $user"
echo "#"
sudo chown $user.$user $HOME/boot-backup-$date

# Backup of Home folder
echo "#"
echo "# Taking rsync backup of $HOME"
echo "#"
if [ -e "$HOME/.rsync/exclude" ]; then
		echo ""
		echo "#"
		echo "# Your rsync excludes file exists, doing nothing"
		echo "#"
	else
		echo ""
		echo "#"
		echo "# Your rsync excludes file does not exist, creating it at $HOME/.rsync/exclude"
		echo "#"
		mkdir $HOME/.rsync
		touch $HOME/.rsync/exclude
	fi

rsync -azP \
  --bwlimit=$bwlimit \
  --delete \
  --delete-excluded \
  --exclude-from=$HOME/.rsync/exclude \
  --link-dest=../current \
  $HOME $user@$backupserver:Backups/incomplete_back-$date \
  && ssh $user@$backupserver \
  "mv Backups/incomplete_back-$date Backups/back-$date \
  && rm -f Backups/current \
  && ln -s back-$date Backups/current"

# apt-get update then apt-get upgrade -d to update the repo list
# but only download the updates, not install them
echo "#"
echo "# Performing a apt-get update"
echo "#"
sudo apt-get update
echo "#"
echo "# Performing an apt-get upgrade -d to download updates"
echo "#"
sudo apt-get upgrade -d

# Now we setup our LVM snapshot
# This creates a 15GiB logical volume called lvsnap, that is the destination
# for lvroot.
echo "#"
echo "# Creating a $snapsize LVM snapshot called lvsnap with the destination of $primarylv"
echo "#"
sudo lvcreate -L $snapsize -s -n lvsnap $primarylv

# Now finally we perform the apt-get upgrade, without assuming yes incase
# there was a problem with creating your snapshot.
echo "#"
echo "# Performing the real apt-get upgrade"
echo "# Make sure there were no errors with the creation of the LVM snapshot earlier"
echo "#"
sudo apt-get upgrade
