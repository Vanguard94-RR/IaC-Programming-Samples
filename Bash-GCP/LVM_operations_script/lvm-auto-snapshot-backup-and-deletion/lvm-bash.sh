#!/bin/bash
#Shell Script to take lvm snapshot backup and remove old backups automatically

# Please modify below section as per your needs....

KEEP_DAYS=3 #Number of days to keep old snapshot backup
VG=$(vgs -o vg_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g') # LVM volume group we are snapshoting
LV=$(lvs -o lv_name --noheadings | awk 'FNR == 1 {print}' | sed 's/ //g') # Name of LVM-logical volume to take a snapshot of
BACKUP_PREFIX="lvm_snapshot_backup-" # Prefix of snapshot volume name.
SIZE=50G # Amount of disk space to allocate for the snapshot

#


# Create new snapshot

TODAY="$(date +%F)"
NEW_VOLUME="$BACKUP_PREFIX$TODAY"
if ! lvs | grep -q -F "$NEW_VOLUME"; then
	/sbin/lvcreate --size $SIZE --permission r --snapshot "$VG/$LV" --name "$NEW_VOLUME"
else
	echo "Backup already exists: $NEW_VOLUME"
fi

# Cleanup old snapshots

lvs -o lv_name --noheadings | sed -n "s@$BACKUP_PREFIX@@p" | while read DATE; do
	TS_DATE=$(date -d "$DATE" +%s)
	TS_NOW=$(date +%s)
	AGE=$(( (TS_NOW - TS_DATE) / 86400))
	if [ "$AGE" -ge "$KEEP_DAYS" ]; then
		VOLNAME="$BACKUP_PREFIX$DATE"
		/sbin/lvremove -f "$VG/$VOLNAME"
	fi
done

#
