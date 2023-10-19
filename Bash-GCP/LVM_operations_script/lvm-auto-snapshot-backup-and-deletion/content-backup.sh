#!/bin/bash

function LvmFullSnapshotDelete
{
  VG=$(sudo /sbin/vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  LVMSNAPFULL=$(sudo /sbin/lvs --noheadings -o lv_name,snap_PERCENT  2>/dev/null | grep snapbkp | grep 100 |  awk {'print $1'})

  if [ -z "$LVMSNAPFULL"]
  then
  echo "None of LVM Snapshots are 100% full..."
  else
  echo "$LVMSNAPFULL" | while read i; do echo "Deleting 100% full snapshots $i" && sudo /sbin/lvremove -f "$VG/$i"; done || exit 1
  fi
}

function VgCleanupForLvmContentBackup
{
  VG=$(sudo /sbin/vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  LVMSNAPSHOTSIZE="1GB"
  LVMSNAPSHOTSIZECOMP="1"
  VGFREE=$(sudo /sbin/vgs --noheadings --units g  2>/dev/null |  awk {'print int( $7)'})
  VGTOTAL=$(sudo /sbin/vgs --noheadings --units g  2>/dev/null |  awk {'print int( $6)'})

  if [ $VGTOTAL -lt $LVMSNAPSHOTSIZECOMP ]
  then
  echo "The requested snapshost size $LVMSNAPSHOTSIZE is bigger than total volume group size" || exit 1
  fi

  until [ $VGFREE -ge $LVMSNAPSHOTSIZECOMP ]
  do
  sleep 3
  VGFREE=$(sudo /sbin/vgs --noheadings --units g  2>/dev/null |  awk {'print int( $7)'})
  LVSNAPLIST=$(sudo /sbin/lvs --noheadings -o lv_name,snap_percent 2>/dev/null  | grep snapbkp | awk {'print $1'} | head -n 1)

  if [ -z "$LVSNAPLIST" ]; then
  echo "There are no more snapshots left to delete on this volume group $VG" || exit 0
  else
  echo "$LVSNAPLIST" | while read i; do echo "Deleting older snapshot $i" && sudo /sbin/lvremove -f $VG/$i; done || exit 1
  fi
  done
}


function CopyLvmContentBackup
{
  VG=$(sudo /sbin/vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  LV=$(sudo /sbin/lvs -o lv_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  BACKUP_PREFIX="snapbkp-"
  LVMSNAPSHOTSIZE=1GB
  TODAY="$(date +%F-%H-%M)"
  NEW_VOLUME="$BACKUP_PREFIX$TODAY"
  MOUNTPOINT="/tmp/lvmsnap/"
  HNAME=$HOSTNAME

  echo "Checking if there is any full snapshosts and deleting them ..."
  LvmFullSnapshotDelete || exit 1

  echo "Checking VG Free size and cleaning up if it is full..."
  VgCleanupForLvmContentBackup || exit 1

  echo " Creating snapshot $NEW_VOLUME"
  sudo /sbin/lvcreate --size $LVMSNAPSHOTSIZE --permission r --snapshot "$VG/$LV" --name "$NEW_VOLUME" || exit 1

  if [ ! -d $MOUNTPOINT ]
  then
  echo "Creating temporary mountpoint $MOUNTPOINT" &&  mkdir -p $MOUNTPOINT && sudo mount /dev/$VG/$NEW_VOLUME $MOUNTPOINT || exit 1
  else
  sudo mount /dev/$VG/$NEW_VOLUME $MOUNTPOINT || exit 1
  fi

  if ssh openstack@192.168.178.196 '[ ! -d /tmp/backup/$HNAME/ ]'
  then
  echo "Creating backup directory /tmp/backup/$HNAME on backup server &&  ssh openstack@192.168.178.196 mkdir -p /tmp/backup/$HNAME || exit 1
  echo "Starting rsync process...." && sudo rsync -avrzh -e ssh -t $MOUNTPOINT openstack@192.168.178.196:/tmp/backup/$HNAME/ --progress || exit 1
  sudo umount /tmp/lvmsnap || exit 1
  sudo /sbin/lvremove -f "$VG/$NEW_VOLUME" || exit 1
  else
  echo "Starting rsync process...." && sudo rsync -avrzh -e ssh -t $MOUNTPOINT openstack@192.168.178.196:/tmp/backup/$HNAME/ --progress || exit 1
  sudo umount /tmp/lvmsnap || exit 1
  sudo /sbin/lvremove -f "$VG/$NEW_VOLUME" || exit 1
  fi
}
