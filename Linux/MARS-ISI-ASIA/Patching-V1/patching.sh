#! /bin/bash
## PENDING Adjust file to suit ansible
# Maintenance Script

change_name=CHG0267694
inventory_name=inventory
server1_name=kohler-dev.acrolinx.cloud

function pause() {
    read -s -n 1 -p " Press any key to continue . . ."
    echo ""
}

#setup environment

echo "Initializating environment"
#source ~/acrolinx_venv_setup.sh
echo "u@VU3w,MecA6gTMn" >.vault.password

#clone repository
# we must ask for wich repository needs to be cloned
mkdir TICKETS/$change_name

##git clone --recurse-submodules git@gitlab.com:acrolinx/cloud-platform/cloud-deployment-for-kubernetes/ansible-deployment.git

pause

#check repository version

cd ansible-deployment || exit
git checkout master && git pull && git submodule update --init --recursive

# Monitoring must be suspended before this point, preferably before beginning of maintenance

# Stop Acrolinx and PostgreSQL using Ansible:
pause
echo "u@VU3w,MecA6gTMn" >.vault.password
echo
echo " Draining Node "
./ansible-docker-image/ansible-playbook -l $server1_name drain-node.yml -e ansible_ssh_common_args= --check
cp /home/ec2-user/test/ansible-deployment/ansible-run.log /home/ec2-user/test/TICKETS/$change_name/Ansible-Node-Drain-run.log
rm -f /home/ec2-user/test/ansible-deployment/ansible-run.log
echo
echo " Node Drained "
# Create AMI on Amazon Web Server
echo " Preparing for manual AMI creation on AWS Web Portal "
pause
# Uncordon Node
echo " Uncordoning node "
sleep 5
./ansible-docker-image/ansible-playbook -l $server1_name uncordon-node.yml -e ansible_ssh_common_args
cp /home/ec2-user/test/ansible-deployment/ansible-run.log /home/ec2-user/test/TICKETS/$change_name/Ansible-Node-Uncordon-run.log
rm -f /home/ec2-user/test/ansible-deployment/ansible-run.log
# Run main playbook
echo " Preparing to run main playbook 'instance.yaml' "
echo " Please review all previous work done and "
pause
echo " Running main playbook 'instance.yaml' "
echo
./ansible-docker-image/ansible-playbook -l $server1_name instance.yml -e ansible_ssh_common_args=
echo
cp /home/ec2-user/test/ansible-deployment/ansible-run.log /home/ec2-user/test/TICKETS/$change_name/Ansible-Main-run.log
echo " Preparing to run main playbook 'instance.yaml' "
#Finish
echo " Change Complete "
