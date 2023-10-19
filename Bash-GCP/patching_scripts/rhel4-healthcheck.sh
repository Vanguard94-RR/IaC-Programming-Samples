#!/bin/bash
# ------------------------------------------------------------
# Name  : rhel4-healthcheck.sh
# Desc  : Perform basic server health check for RHEL 4 servers
# Group : ETS Linux/Unix Patching
# Author: Gene Ordanza <geronimo.ordanza@fisglobal.com>
# History: 20141022 Initial draft
#
# Note  : Initially, this was port of health_check.sh for RHEL5/6 servers.
#         However, it turns out that some of bash functionality in RHEL5/6
#         was bit wonky in older bash. For one thing, bash arrays doesn't work
#         the same way in RHEL4. So I ended up re-writing the code somewhat.
#
# TODO  : 1. Rewrite display of available UPDATES to have similar output with
#            original health_check.
#         2. Check for any Oracle process running on the server.
# ------------------------------------------------------------

format=" %25s | %-48s\n"

# Check server if using RHEL4 and that it's running as root
function checkUserOS() {
    if [ "$(uname -s)" != 'Linux' -o ! -f /etc/redhat-release ]; then
        echo "This script only runs on RHEL servers."; exit 1

    elif [ "$(id -u)" != "0" ]; then
        echo "You need to run this script as root!"; exit 1

    elif ! grep Nahant /etc/redhat-release &>/dev/null; then
        echo "Sorry, this script was written for RHEL 4 release"; exit 1
    fi
}

# Get Bastion IP Address
function bastion() {
    netstat --numeric-hosts|awk '/ssh/ {print $5}' > bastions.txt
    sort bastions.txt|uniq|awk -F":" '{printf "%-10s\n", $1}' > sorted.txt
    cat sorted.txt ; rm -f bastions.txt sorted.txt
}

# Get Proper Uptime
function display_uptime() {
    uptime=$(</proc/uptime)
    uptime=${uptime%%.*}
    secs=$(( uptime%60 ))
    mins=$(( uptime/60%60 ))
    hour=$(( uptime/60/60%24 ))
    days=$(( uptime/60/60/24 ))
    echo "$days:D $hour:H $mins:M $secs:S"
}

# Get hardware information
function hardware() {
    local hardware="$(dmidecode|grep -i product|head -n1|awk -F: '{print $2}')"
    echo $hardware
}

# Get memory
function memory() {
    local val="$(free -m|awk '/^Mem:/ { print $2 }')"
    echo $val MB
}

# Get date of last OS patch
function lastpatch() {
    local val="$(rpm -qa --last|head -n1|awk '{print $1=""; print $0}')"
    echo $val
}

# Get third-party package
function thirdparty() {
    echo "PACKAGE NAME                   VENDOR"
    rpm -qa --qf '|%{NAME}-%{VERSION}-%{RELEASE}|%{VENDOR}\n'|sort>non-rhel.txt
    awk -F"|" 'BEGIN {var=1} {if ($0 !~ "Red Hat")
                     {printf "%28s %-30s %-20s\n",$1,$2,$3;var=0}}
               END {if (var==1) printf "%33s", "none"}' non-rhel.txt
    rm -f non-rhel.txt
}


# Get Proxy used for up2date
function proxy() {
    grep httpProxy= /etc/sysconfig/rhn/up2date|sed 's/httpProxy=//g'|sed 's/:/ PORT: /g'
}


# Check if Oracle packages are installed
function oracle_asm() {
    if rpm -qa | grep -q oracleasm; then
        echo "`rpm -qa|grep oracleasm|head -n1`"
    else
        echo "None"
    fi
}

# Check if Oracle DB process is running
function ora_asm_proc() {
    if ps -ef | grep -v grep | grep asm_pmon &>/dev/null; then
        oracproc=$(ps -ef|grep -v grep|grep asm_pmon|awk '{ print $NF }')
        echo "$oracproc"
    else
        echo "No running Oracle ASMLib process"
    fi
}

# Check for the type of server authentication
function check_auth() {
    if [ -f /etc/init.d/vasd ]; then
        echo "VAS authentication"
    elif [ -f /etc/init.d/boksm ]; then
        echo "BoKs Authentication"
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

# Check Disk Usage for each File System
function diskspace() {
    echo "USAGE  FILESYSTEM"
    df -h|grep -v Used|awk 'NF > 1'|awk '{print $(NF-1), $NF}' > temp.txt
    awk '{printf "%34s  %s\n", $1, $2}' temp.txt
}

# Check for File System over 80% threshold
function threshold() {
    echo "USAGE  FILESYSTEM"
    sed 's/%//' temp.txt | \
    awk 'BEGIN {var=1} {if ($1>79) {printf "%33s%%  %s\n", $1,$2; var=0}}
    END {if (var == 1) printf "%33s", "NONE"}'
    rm -f temp.txt
}



# Display line delimeter for header
function lineprint() {
    echo
    for (( i=1; i<70; i++ )); do echo -n '='; done;
}

# Display report header
function header() {
    [[ -z $1 ]] && local ticket="<none given>" || local ticket=$1
    lineprint
    printf "\n%45s\n\n" "SYSTEM HEALTH CHECK"
    echo " CHANGE : $ticket"
    echo " DATE   : `date`"
    lineprint; echo
}

# Althernative for rhel4
function output() {

    printf "$format" "HOSTNAME"            `hostname`
    printf "$format" "IP ADDRESS"          `hostname -i`
    printf "$format" "BASTIONS"            "$(bastion)"
    printf "$format" "UPTIME"              "$(display_uptime)"
    printf "$format" "OS TYPE"             `uname -s`
    printf "$format" "KERNEL RELEASE"      `uname -r`
    printf "$format" "OS RELEASE VERSION"  `rpm -qa redhat-release*`
    printf "$format" "OS RELEASE NAME"     "`cat /etc/redhat-release`"
    printf "$format" "ARCHITECTURE"        `uname -m`
    printf "$format" "HARDWARE"            "$(hardware)"
    printf "$format" "NO. OF PROCESSORS" "$(cat /proc/cpuinfo|grep processor|wc -l)"
    printf "$format" "MEMORY"              "$(memory)"
    printf "$format" "LAST OS PATCH"       "$(lastpatch)"
    printf "$format" "THIRD PARTY PACKAGE" "$(thirdparty)"
    printf "$format" "PROXY INFO"          "$(proxy)"
    printf "$format" "REPO LIST"           `up2date --show-channels`
    printf "$format" "UPDATES"             `echo to_be_implemented`
    printf "$format" "ORACLE ASMLib"       "$(oracle_asm)"
    printf "$format" "ORACLE PROCESS"   `echo to_be_implemented` #ora_asm_proc()
    printf "$format" "AUTHENTICATION"      "$(check_auth)"
    printf "$format" "HPSA AGENT STATUS"   "$(hpsa_agent)"
    printf "$format" "MOUNTED DISK SPACE"  "$(diskspace)"
    printf "$format" "FS OVER 80% THRESHOLD" "$(threshold)"
}

# Main program
function main() {
    checkUserOS
    header $1
    output
    # This need to be implemented under UPDATES
    up2date --list
}

main $1
