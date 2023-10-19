#!/bin/bash

#Cleanup 100% full snapshots

function LvmFullSnapshotDelete

{
VG=$(vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
LVMSNAPFULL=$(lvs --noheadings -o lv_name,snap_PERCENT  2>/dev/null | grep lvm_snapshot_backup | grep 100 |  awk {'print $1'})

echo "$LVMSNAPFULL" | while read i; do echo "Deleting 100% full snapshots $i" && /sbin/lvremove -f "$VG/$i"; done || exit 1 

}

#Cleanup older snapshots if VG is full
function VgCleanup
{
  VG=$(vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  LVMSNAPSHOTSIZE=10G
  VGFREE=$(vgs --noheadings --units g  2>/dev/null |  awk {'print int( $7)'})
  LVSNAPLIST=$(lvs --noheadings -o lv_name,snap_percent 2>/dev/null  | grep snap | awk {'print $1'} | head -n 1)
  
  until [ $VGFREE -ge $LVMSNAPSHOTSIZE ]
  
  do 
  	
  	echo "$LVSNAPLIST" | while read i; do echo "Deleting older snapshot $i" && /sbin/lvremove -f "$VG/$i"; done || exit 1 
  
  done
}	

#create lvm snapshot
function LvmSnapshotCreate
{
  VG=$(vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  LV=$(lvs -o lv_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  BACKUP_PREFIX="lvm_snapshot_backup-"
  LVMSNAPSHOTSIZE=10G
  TODAY="$(date +%F-%H-%M)"
  NEW_VOLUME="$BACKUP_PREFIX$TODAY"
  
  echo "Checking if there is any full snapshosts and deleting them ..." 
  $(LvmFullSnapshotDelete) || exit 1  
  echo "Checking VG Free size and cleaning up if it is full..." 
  $(VgCleanup) || exit 1 
  echo " Creating snapshot $NEW_VOLUME"
  /sbin/lvcreate --size $LVMSNAPSHOTSIZE --permission r --snapshot "$VG/$LV" --name "$NEW_VOLUME" || exit 1 
  
}

function CopyContentBackup
{ 
  VG=$(vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g')
  BACKUP_PREFIX="lvm_snapshot_backup-"
  TODAY="$(date +%F-%H-%M)"
  NEW_VOLUME="$BACKUP_PREFIX$TODAY"
  MOUNTPOINT="/tmp/lvmsnap/"
  HNAME=$(echo $HOSTNAME | awk -F. '{print $1}')
  
  if [ ! -d $MOUNTPOINT ] 
  then
  mkdir -p $MOUNTPOINT && mount $VG/$NEW_VOLUME $MOUNTPOINT || exit 1
  fi
  
  if [ ! -d $MOUNTPOINT ] 
  then
  mkdir -p $HNAME && rsync -arz --progress -e ssh $MOUNTPOINT* user@server:/srv/backup/$HNAME/ || exit 1
  
  unmount /tmp/lvmsnap || exit 1
  
  /sbin/lvremove -f "$VG/$NEW_VOLUME" || exit 1 
  fi
}
