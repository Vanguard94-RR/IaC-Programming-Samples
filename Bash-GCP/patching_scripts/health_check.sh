#!/bin/sh
# --------------------------------------------------------
# Name   : health_check.sh
# Desc   : Perform basic server health check
# Group  : ETS Linux/Unix Patching
# Contributors :
#          Gene Ordanza II <geronimo.ordanza@fisglobal.com>
#          Aaron Wyllie <Aaron.Wyllie@fisglobal.com>
# History: 20140610 (GA0) initial draft
#         +20140616 (ATW) added repolist function
#         +20140616 (ATW) added OS RELEASE VERSION
#         +20140827 (ATW) added pending package updates
#         +20140827 (ATW) added proper uptime information
#         +20140827 (ATW) added rhn proxy information
#         +20140921 (GAO) added report header that accept Change ticket arg
#         +20140921 (GAO) added VAS authentication check
#         +20141001 (GAO) added check for third-party packages
#         +20141001 (GAO) added bastion resolution
# --------------------------------------------------------

echo "Checking for live updates..."

# Output formatting
format1=" %25s | %-48s\n"

# Check server if RHEL 5/6 release and that it's running as root.
function checkUserOS() {
    if [ "$(uname -s)" != 'Linux' -o ! -f /etc/redhat-release ]; then
        echo "This script only runs on RHEL servers."; exit 1

    elif [ "$(id -u)" != "0" ]; then
        echo "You need to run this script as root!"; exit 1

    elif grep "release 4" /etc/redhat-release &>/dev/null; then
        echo "Sorry, this script only run on RHEL 5 and above release."; exit 1

    fi
}

# Get Bastion IP Address
function bastion() {
    netstat --numeric-host|awk '/ssh/ {print $5}' > bastions.txt
    sort bastions.txt|uniq|awk -F":" '{printf "%-10s\n",$1 }' > sorted.txt
    awk 'BEGIN {var=""} {printf "%28s %-30s\n", var, $1}' sorted.txt
    rm -f bastions.txt sorted.txt
}

# Get Proper Uptime ...
function display_uptime() {
    uptime=$(</proc/uptime)
    uptime=${uptime%%.*}
    secs=$(( uptime%60 ))
    mins=$(( uptime/60%60 ))
    hour=$(( uptime/60/60%24 ))
    days=$(( uptime/60/60/24 ))

    echo "$days:D $hour:H $mins:M $secs:S"
}


# Display third-party (non-RHEL packages) application
function thirdparty() {
    rpm -qa --qf '|%{NAME}-%{VERSION}-%{RELEASE}|%{VENDOR}\n'|sort> non-rhel.txt
    awk -F"|" 'BEGIN {var=1} {if ($0 !~ "Red Hat")
                                {printf "%28s %-30s %-20s\n",$1,$2,$3;var=0}}
               END {if (var == 1) printf "%33s", "none"}' non-rhel.txt
    rm -f non-rhel.txt
}

# Display Configured YUM Repositories
function channels() {
    rhn-channel -l | awk '{print $1}' > channel_list.txt
    awk '{printf "                             %-34s\n", $1}' channel_list.txt
    rm -f channel_list.txt
}


# Check if there is a package update from RHN/Satellite
function package_updates() {
    case `yum check-update &>/dev/null; echo $?` in
        "0") echo "No pending package updates available" ;;
        "1") echo "Error occured! Use yum check-update manually";;
        "100") echo "Pending package updates are available ..." ;;
    esac
}

# Check for the type of server authentication used (ie. BoKs/VAS/Local)
function check_auth(){
    if [ -f /etc/init.d/vasd ]; then
        service vasd status
    elif [ -f /etc/init.d/boksm ]; then
        service boksm status
    else
        echo "Local Accounts"
    fi
}


# Check for running HPSA agent
function hpsa_agent() {
    if [ -f /etc/init.d/opsware-agent ]; then
        service opsware-agent status
    else
        echo "None"
    fi
}

# Display Disk Usage for each File System
function diskspace() {
    df -h | grep -v Used | awk 'NF > 1' | awk '{print $(NF-1), $NF}' > temp.txt
    awk '{printf "%34s  %s\n", $1, $2}' temp.txt
}


# Display Pending Package Updates
function pending_updates() {
    yum -q check-update | awk 'NR!=1' > pending.txt
    awk '{printf "                             %-30s %s\n", $1, $2}' pending.txt
    rm -f pending.txt
}


# Check for File System over 80% threshold.
function threshold() {
    sed 's/%//' temp.txt | \
    awk 'BEGIN {var=1} {if ($1>79) {printf "%33s%%  %s\n", $1,$2; var=0}}
    END {if (var == 1) printf "%33s", "None"}'
    rm -f temp.txt
}


# Delete leading spaces for display and alignment.
function leadspace() {
    echo "$1" | sed -e 's/^[ \t]*//'
}


# This is where most of the processing is done.
function helper() {

    case "$1" in

       "bastion") echo "IP Address"
                  bastion
                  ;;

        "uptime") display_uptime
                  ;;

      "hardware") local hardware="$(dmidecode | grep -i product | head -n1 | \
                  awk -F: '{ print $2}')"
                  leadspace "$hardware"
                  ;;

        "memory") local val="$(free -m | awk '/^Mem:/ { print $2 }')"
                  echo "$val MB"
                  ;;

     "lastpatch") local update="$(rpm -qa --last| head -n1 | \
                   cut -d" " --complement -s -f1)"
                  leadspace "$update"
                  ;;

    "thirdparty") echo "PACKAGE NAME                   VENDOR"
                  thirdparty
                  ;;

         "proxy") grep httpProxy= /etc/sysconfig/rhn/up2date | sed 's/httpProxy=//g' | \
                  sed 's/:/ PORT: /g'
                  ;;

      "channels") echo "RHN Channels ..."
                  channels
                  ;;

        "update") package_updates
                  ;;

       "pending") echo "PACKAGE NAME                   VERSION"
                  pending_updates
                  ;;

    "oracle_asm") if rpm -qa | grep -q oracleasm ; then
                      echo "`rpm -qa|grep oracleasm|head -n1`"
                  else
                      echo "None"
                  fi
                  ;;

  "ora_asm_proc") if ps -ef | grep -v grep | grep asm_pmon &>/dev/null; then
                      oracproc=$(ps -ef|grep -v grep|grep asm_pmon|awk '{ print $NF }')
                  echo "$oracproc"
                  else
                      echo "None"
                  fi
                  ;;

          "auth") check_auth
                  ;;

          "hpsa") hpsa_agent
                  ;;

     "diskspace") echo "USAGE  FILESYSTEM"
                  diskspace
                  ;;

     "threshold") echo "USAGE  FILESYSTEM"
                  threshold
                  ;;

               *) echo "** INVALID OPTION **"
                  ;;
    esac

}


# Display formatted output
function output() {

    # Variable array (key) initialization
    declare -a key=(
        "HOSTNAME"
        "IP ADDRESS"
        "BASTIONS"
        "UPTIME"
        "OS TYPE"
        "KERNEL RELEASE"
        "OS RELEASE VERSION"
        "OS RELEASE NAME"
        "ARCHITECTURE"
        "HARDWARE"
        "NO. OF PROCESSORS"
        "MEMORY"
        "DATE OF LAST OS PATCH"
        "THIRD-PARTY PACKAGES"
        "PROXY INFO"
        "REPOLIST"
        "UPDATES"
        "PENDING UPDATES"
        "ORACLE ASMLib"
        "ORACLE ASMLib PROCESS"
        "AUTHENTICATION"
        "HPSA AGENT STATUS"
        "MOUNTED FS/DISK SPACE"
        "FS OVER 80% THRESHOLD")


    # Variable array (value) for corresponding initialization
    declare -a value=(
        "$(hostname)"
        "$(hostname -i)"
        "$(helper "bastion")"
        "$(helper "uptime")"
        "$(uname -s)"
        "$(uname -r)"
        "$(rpm -qa redhat-release*)"
        "$(cat /etc/redhat-release)"
        "$(uname -m)"
        "$(helper "hardware")"
        "$(cat /proc/cpuinfo|grep processor | wc -l)"
        "$(helper "memory")"
        "$(helper "lastpatch")"
        "$(helper "thirdparty")"
        "$(helper "proxy")"
        "$(helper "channels")"
        "$(helper "update")"
        "$(helper "pending")"
        "$(helper "oracle_asm")"
        "$(helper "ora_asm_proc")"
        "$(helper "auth")"
        "$(helper "hpsa")"
        "$(helper "diskspace")"
        "$(helper "threshold")"
        )

    for (( i=0; i<${#key[@]}; i++ )); do
        printf "$format1" "${key[i]}" "${value[i]}"
    done
}


# Diplay line delimeter for headers
function lineprint() {
    echo
    for (( i=1; i<70; i++ )); do echo -n '='; done;
#   echo -e "\n"
}


# Display report header
function header() {
    [[ -z $1 ]] && local ticket="<none given>" || local ticket=$1
    lineprint
    printf "\n%45s\n\n" "SYSTEM HEALTH CHECK"
    echo " CHANGE : $ticket"
    echo " DATE   : `date`"
    lineprint;echo
}


# Main program
function main() {
    checkUserOS
    header $1
    output
}

main $1
