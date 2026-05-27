#!/bin/bash
# Purpose: Read Comma Separated CSV File
# Author: Mizael Morales
# ------------------------------------------
RED='\033[1;31m'
BRed='\033[1;31m\]'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BO='\033[0;33m'
LC='\033[1;36m'
LGREEN='\033[1;32m'
LGRAY='\033[0;37m'
NC='\033[0m'

INPUT=data-script.csv
OLDIFS=$IFS
IFS=','
[ ! -f $INPUT ] && {
    echo "$INPUT Archivo no encontrado"
    exit 99
}

clear
echo "Iniciando acceso de cluster..."

echo "" > log4j.csv 

while read name ip cluster region project data; do
    echo "name : $name"
    echo "ip   : $ip"
    echo "cluster : $cluster"
    echo "region  : $region"
    echo "project : $project"
    echo "data     :$data"
    
    gcloud container clusters get-credentials $name --zone $region --project $project
    echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} gcloud container clusters get-credentials $name --zone $region --project $project ${WHITE}"
    echo -e "${LGRAY}EXEC: ${NC} ${YELLOW} gcloud compute --project=$project security-policies create cve-canary ${WHITE}"
    echo -e "${LGRAY}EXEC: ${NC} ${WHITE} gcloud compute --project=$project security-policies rules create 1 --action=deny-403 --security-policy=cve-canary --expression=evaluatePreconfiguredExpr\(\'cve-canary\'\) ${WHITE}"
    echo -e "${LGRAY}EXEC: ${NC} ${WHITE} gcloud compute --project=$project security-policies rules create 2147483647 --action=deny-403 --security-policy=cve-canary --description="Default rule, higher priority overrides it" --src-ip-ranges=\* ${WHITE}"
    echo -e "${LGRAY}EXEC: ${NC} ${WHITE} gcloud compute --project=$project security-policies rules create 100 --action=allow --security-policy=cve-canary --description="IPs WAF" --src-ip-ranges=35.238.84.248,34.121.197.40 ${WHITE}"
    gcloud compute --project=$project security-policies create cve-canary

    gcloud compute --project=$project security-policies rules create 2147483647 --action=deny-403 --security-policy=cve-canary --description="Default rule, higher priority overrides it" --src-ip-ranges=\*

    #Actualizar regla por defecto
    gcloud compute --project=$project security-policies rules create 1 --action=deny-403 --security-policy=cve-canary --expression=evaluatePreconfiguredExpr\(\'cve-canary\'\)
    
    gcloud compute --project=$project security-policies rules create 100 --action=allow --security-policy=cve-canary --description="IPs WAF" --src-ip-ranges=35.238.84.248,34.121.197.40

    gcloud compute backend-services list --project $project --format=json | jq -r '.[].name' > backend-list.txt

    gcloud compute --project=$project security-policies update cve-canary --json-parsing=STANDARD

    gcloud compute ssl-policies create sslsecure --profile MODERN --min-tls-version 1.2

    gcloud beta compute ssl-certificates create wildcarddigicertgnpcommx2026 --project=$project --global --description=wildcarddigicertgnpcommx2026 --certificate=bundle.cer --private-key=KEY_gnp.com.mx_Marzo_2024.key
    
    gcloud services enable containersecurity.googleapis.com
    IFS=$OLDIFS 
    for i in $(cat backend-list.txt);
    do
      echo -e "${LGRAY}BACKEND: $i "
      echo -e "${LGRAY}EXEC: ${NC} ${WHITE} gcloud compute --project=$project backend-services update $i --security-policy=cve-canary --global${WHITE}"
      gcloud compute --project=$project backend-services update $i --security-policy=cve-canary --global
    done 
    OLDIFS=$IFS
    IFS=','
done <$INPUT
IFS=$OLDIFS
