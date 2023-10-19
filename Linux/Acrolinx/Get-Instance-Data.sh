#! /bin/bash
# @Purpose             Gathers dataof the given instance name
# @Background  Requires that awscli is installed.
## @Usage:              ./instance-data
##
# export AWS Credentials
set -a
. ./AWS-Credentials
set +a

# Variables
CHANGE_NAME=""
INSTANCE_ID=""
INSTANCE_NAME=""
AWS_REGION=""
AWS_ZONE=""
AMI_CREATED=""
IMAGE_STATE=""
ZONE=""
REGION=""
DATE=$(date +%Y-%m-%d_%H-%M)
AMI_NAME=""
AMI_DESCRIPTION=""

# Script
# CHG0268983
# bajajfinserv.acrolinx.cloud
printf "<========================================================>\n"
printf "<======== Acrolinx Standard Instance Maintenance ========>\n"
printf "<============== AWS Instance Data Gatherer ==============>\n"
printf "<========================================================>\n"
#read -r -p "Enter Change name as in ticket: " CHANGE_NAME
read -r -p "Enter Instance name as in Portal/Ticket: " INSTANCE_NAME
#read -r -p "Enter Region as in Portal: " AWS_REGION
printf "\n"
aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" --output text --query "Reservations[*].Instances[*].InstanceId" >GET_INST_ID
INSTANCE_ID=$(<"GET_INST_ID")
printf "Instance ID: %s\n" "$INSTANCE_ID"
aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" --output text --query 'Reservations[*].Instances[*].Placement[].AvailabilityZone' >ZONE
AWS_ZONE=$(<"ZONE")
printf "Instance Zone: %s\n" "$AWS_ZONE"
aws ec2 describe-availability-zones --filters "Name=zone-name,Values=$AWS_ZONE" --output text --query "AvailabilityZones[].RegionName[]" >REGION
AWS_REGION=$(<"REGION")
printf "Instance Region: %s\n" "$AWS_REGION"
printf "\n"
