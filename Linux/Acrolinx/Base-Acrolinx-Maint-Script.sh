#!/bin/bash -
#title          :Base-Acrolinx-Maint-Script.sh
#description    :Executes an acrolinx standard instance maintenance script
#               :
#author         :Manuel Cortes
#date           :20221007
#version        :1.5
#usage          :./Base-Acrolinx-Maint-Script.sh
#notes          : This is a fully operational script, on all ansible commands there is a "--check" arguments that makes the command dry run
#bash_version   :5.0.17(1)-release
#============================================================================
# Maintenance Script

# Variables
CHANGE_NAME=""

SERVER_NAME=""

#check_mode=""

# Functions

function pause() {
    read -r -s -n 1 -p " Press any key to continue . . ."
    echo ""
}
function pause2() {
    read -r -s -n 1 -p " press any key to continue . . ."
    echo ""
}

#Beginnig of Script

## Input change name to create directory
printf "<========================================================>\n"
printf "<======== Acrolinx Standard Instance Maintenance ========>\n"
printf "<========================================================>\n"
read -r -p "Enter Change name as in ticket: " CHANGE_NAME

## Input device/server name as indicated on ticket
printf "Enter server(s) name as per ticket, if several devices are been worked at once,\n"
read -r -p "please separate them with a space: " SERVER_NAME
printf "\n"
printf "Are %s\nand $SERVER_NAME \ncorrect?\n" "$CHANGE_NAME"
read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
printf "\n"
printf "Change %s\n" "$CHANGE_NAME"
printf "Server(s) %s\n \n" "$SERVER_NAME"

## Setup python environment
printf "Initializating environment \n"
sleep 1
# shellcheck source=/dev/null
source ~/acrolinx_venv_setup.sh
echo "u@VU3w,MecA6gTMn" >.vault.password

## Clone repository and check version
printf "Creating change folder ~/TICKETS/%s\n \n" "$CHANGE_NAME"
sleep 1
mkdir TICKETS/"$CHANGE_NAME"
printf "Folder created\n"
sleep 1
ls ~/TICKETS/"$CHANGE_NAME"
printf "\n"
printf "Cloning repository \n"
sleep 1
cd TICKETS || exit
rm -rf ansible-deployment # This deletes de old repo directory to allow next command download a new one
git clone --recurse-submodules git@gitlab.com:acrolinx/cloud-platform/cloud-deployment-for-kubernetes/ansible-deployment.git
printf "\n"
printf "Checking repository version \n"
sleep 1
cd ansible-deployment || exit
git checkout master && git pull && git submodule update --init --recursive

# Monitoring must be suspended before this point, preferably before beginning of maintenance

## Stop Acrolinx and PostgreSQL by draining the node using Ansible:

echo "u@VU3w,MecA6gTMn" >.vault.password
printf "\n"
printf " Preparing Node to be drained do you want to proceed? \n"
read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
printf "\n"
printf " Draining Node\n"
sleep 5
./ansible-docker-image/ansible-playbook -l "$SERVER_NAME" drain-node.yml -e ansible_ssh_common_args= --check
cp /home/ec2-user/TICKETS/ansible-deployment/ansible-run.log /home/ec2-user/TICKETS/"$CHANGE_NAME"/"$CHANGE_NAME-Ansible-Node-Drain-run.log"
rm -f /home/ec2-user/TICKETS/ansible-deployment/ansible-run.log
printf "\n"
printf " Node Drained \n"
printf "\n"
## Create AMI on Amazon Web Server
printf " Please manually create AMI(s) with Automated script or in AWS portal, when status change to Available then \n"
pause2

## Uncordon Node using Ansible
printf " Uncordoning node \n"
sleep 5
./ansible-docker-image/ansible-playbook -l "$SERVER_NAME" uncordon-node.yml -e ansible_ssh_common_args= --check
cp /home/ec2-user/TICKETS/ansible-deployment/ansible-run.log /home/ec2-user/TICKETS/"$CHANGE_NAME"/"$CHANGE_NAME-Ansible-Node-Uncordon-run.log"
rm -f /home/ec2-user/TICKETS/ansible-deployment/ansible-run.log
# Run main playbook
printf " Preparing to run main playbook 'instance.yaml' \n"
sleep 1
printf " Please review all previous work done and \n"
pause
sleep 1
printf " Running main playbook 'instance.yaml' \n"
sleep 5
./ansible-docker-image/ansible-playbook -l "$SERVER_NAME" instance.yml -e ansible_ssh_common_args= --check
cp /home/ec2-user/TICKETS/ansible-deployment/ansible-run.log /home/ec2-user/TICKETS/"$CHANGE_NAME"/"$CHANGE_NAME-Ansible-run.log"

#Finish
sleep 5
printf " Change Complete \n"
printf "You can find the log files in:\n"
cd ~ || exit
ls -plah TICKETS/"$CHANGE_NAME"
rm -rf TICKETS/"$CHANGE_NAME"
