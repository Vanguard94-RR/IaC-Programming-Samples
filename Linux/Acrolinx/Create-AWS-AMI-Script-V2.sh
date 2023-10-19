#! /bin/bash
# @Purpose             Creates an image (AMI) of the given EC2 instance
# @Background  Requires that awscli is installed. Assumes that the
## instance running this command has the permission ec2:CreateImage assigned via IAM.
## Automatically get instance data
## @Usage:              ec2-create-image
##
#
# export AWS Credentials
set -a
. ./AWS-Credentials
set +a

# Variables
AMI_CREATED=""
AMI_DESCRIPTION=""
AMI_DESCRIPTION="$CHANGE_NAME-$INSTANCE_ID-$DATE"
AMI_NAME=""
AMI_NAME="$CHANGE_NAME-$INSTANCE_ID-$DATE"
AWS_REGION=""
AWS_ZONE=""
CHANGE_NAME=""
DATE=$(date +%Y-%m-%d_%H-%M)
IMAGE_STATE=""
INSTANCE_ID=""
INSTANCE_NAME=""
REGION=""
ZONE=""

# Functions

function pause() {
    read -r -s -n 1 -p " Press any key to continue . . ."
    echo ""
}

function checker() {
    while true; do
        aws ec2 describe-images --image-id "$AMI_CREATED" --region "$AWS_REGION" | grep State >image-state
        IMAGE_STATE=$(<"image-state")
        printf "%s\n" "$IMAGE_STATE"
        if [ "$IMAGE_STATE" == '            "State": "available",' ]; then
            return 1
        else
            sleep 15
        fi
    done
}
# Script
#
printf "<========================================================>\n"
printf "<======== Acrolinx Standard Instance Maintenance ========>\n"
printf "<======= AWS AMI Creator for Standard Maintenance =======>\n"
printf "<========================================================>\n"
read -r -p "Enter Change name as in ticket: " CHANGE_NAME
read -r -p "Enter Instance name as in Portal/Ticket: " INSTANCE_NAME
printf "\n"

## Gather Instance Data
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

## Variable confirmation

AMI_NAME="P-$CHANGE_NAME-$INSTANCE_NAME-$DATE"
AMI_DESCRIPTION="$CHANGE_NAME-$INSTANCE_NAME-$DATE"
printf "Are %s\nand $INSTANCE_NAME \nand $AWS_REGION \ncorrect?\n" "$CHANGE_NAME"
read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
printf "\n"
printf " This is going to create an AMi for %s do you want to proceed \n" "$INSTANCE_NAME"
read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
printf "\n"

# image creation
aws ec2 create-image --instance-id "$INSTANCE_ID" --region "$AWS_REGION" --name "$AMI_NAME" --description "$AMI_DESCRIPTION" --no-reboot --output text >AMI
AMI_CREATED=$(<"AMI")
printf "\n"
printf "Image created %s" "$AMI_CREATED"
printf "\n"
touch image-state
checker
printf "AMI created: %s, $IMAGE_STATE\n" "$AMI_CREATED"
#rm -rf AMI image-state GET_INST_ID ZONE REGION
