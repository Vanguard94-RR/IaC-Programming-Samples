# Cleanup 100% full snapshots
function LvmFullSnapshotDelete
{
  local LVM_FULL_SNAPSHOT=($(/sbin/lvs --noheadings -S 'lv_attr =~ ^s' | grep -w 100.00 | awk '{print $1}'))
  local VG=($(/sbin/lvs --noheadings -S 'lv_attr =~ ^s' | grep -w 100.00 |  awk '{print $2}') )
  local COUNT=${#VG[@]}

  for (( i = 0; i < $COUNT; i++ )); do
  sudo /sbin/lvremove -f "${VG[$i]}/${LVM_FULL_SNAPSHOT[$i]}"; done || exit 1
}

# Cleanup 100% full snapshots
function LvmFullSnapshotDelete
{
  local LVM_FULL_SNAPSHOT=$( /sbin/lvs --noheadings -S 'lv_attr =~ ^s' | grep -w 100.00 | awk '{print $2"/"$1}')

  if [ ! -z "$LVM_FULL_SNAPSHOT" ]; then
    echo $LVM_FULL_SNAPSHOT | while read i;
    do /sbin/lvremove -f $i || exit 1;
    done
  else
    exit 0
  fi
}

