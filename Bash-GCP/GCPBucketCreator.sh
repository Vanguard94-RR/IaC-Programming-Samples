#!/bin/bash -
#File name      :bucketcreator.sh
#Description    :Script to create Bucket in specified project
#Author         :Manuel Cortes
#Date           :20231018
#Version        :v1.0.0
#Usage          :./bucketcreator.sh or bash bucketcreator.sh
#Notes          :
#Bash_version   :5.1.16(1)-release
#============================================================================

WHITE='\033[1;37m'
LCYAN='\033[1;36m'
YELLOW='\033[1;33m'
LGREEN='\033[1;32m'
LGRAY='\033[0;37m'
LBLUE='\033[1;34m'
NC='\033[0m'
BLINKO='\033[5m'
BLINKC='\033[0m'

#Confirmar Proyecto con GCloud
echo -e
echo -e "${LGREEN} >>----GNP Cloud Infrastructure Team----<<${NC}"
echo -e "${LGREEN} >>-------Standard Bucket Creation------<<${NC}"
echo -e
echo -e "${YELLOW}This is going to create a bucket with the following specs: ${NC}"
echo -e "${WHITE}Single Region: ${LGREEN}us-central1 ${NC}"
echo -e "${WHITE}Storage Class: ${LGREEN}Standard${NC}"
echo -e "${WHITE}Bucket Level Access: ${LGREEN}Uniform${NC}"
echo -e "${WHITE}Public Acces Prevention: ${LGREEN}True${NC}"

echo -e
read -r -p "Enter Your GCP Project ID (Default: my-project): " projectid
projectid=${projectid:-my-project}
echo -e
read -r -p "Enter Your Bucket Name (Default: my-bucket): " bucket
bucket=${bucket:-my-bucket}
echo -e
read -r -p "Enter Bucket Access Control (Default: Fine-grained, Option: Uniform): " access
access=${access:-Fine-grained}
echo -e
gcloud config set project "$projectid"
echo -e
echo -e "${LCYAN}Creating Bucket...${NC}"
echo -e
if [[ $access == Fine-grained ]]; then
    gcloud storage buckets create gs://"$bucket" --default-storage-class="standard" --no-uniform-bucket-level-access --project="$projectid" --location="us-central1" --public-access-prevention
else
    gcloud storage buckets create gs://"$bucket" --default-storage-class="standard" --uniform-bucket-level-access --project="$projectid" --location="us-central1" --public-access-prevention
fi
echo
