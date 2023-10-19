#!/bin/bash

#create lvm snapshot

function LvmSnapshotBackup
{

VG=$(vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g') # LVM volume group we are snapshoting
LV=$(lvs -o lv_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g') # Name of LVM-logical volume to take a snapshot of
VG_TOTAL=$(vgs --units m | awk 'NR > 1 {print int($6)}') #To check total VG size
VG_USED=$(vgs --units m | awk 'NR > 1 {print int($7)}') #To check usage of VG 
percent=$(awk "BEGIN { pc=100*${VG_USED}/${VG_TOTAL}; i=int(pc); print (pc-i<0.5)?i:i+1 }") #To print how much % VG is used
BACKUP_PREFIX="lvm_snapshot_backup-" # Prefix of snapshot volume name.
SIZE=50G # Amount of disk space to allocate for the snapshot
TODAY="$(date +%F)"
NEW_VOLUME="$BACKUP_PREFIX$TODAY"


if ! lvs | grep -q -F "$NEW_VOLUME" && [$percent -lt 80]; then
	echo " Creating snapshot $NEW_VOLUME"
		/sbin/lvcreate --size $SIZE --permission r --snapshot "$VG/$LV" --name "$NEW_VOLUME"

else
	echo "Backup already exists: $NEW_VOLUME and/or $VG has left only only $percent %"
fi
}

# Cleanup old snapshots

function LvmSnapshotBackupDelete

{
	lvmsnapfull=$(lvs --noheadings -o lv_name,snap_percent  2>/dev/null | grep lvm_snap | grep 100 |  awk {'print $1'})
	VG=$(vgs -o vg_name --noheadings 2>/dev/null | awk 'FNR == 1 {print}' | sed 's/ //g')

		echo "$lvmsnapfull" | while read i; do echo "Deleting 100% full snapshots $i" && /sbin/lvremove -f "$VG/$i"; done

}
