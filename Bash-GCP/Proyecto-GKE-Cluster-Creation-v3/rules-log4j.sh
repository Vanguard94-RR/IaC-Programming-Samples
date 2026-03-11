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
GREEN='\033[0;32m'
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
    
    # Detectar ambiente (PRO vs QA/UAT)
    if [[ $project == *"-pro"* ]]; then
        AMBIENTE="PRO"
        echo -e "${YELLOW}Ambiente detectado: PRO${NC}"
    elif [[ $project == *"-qa"* ]] || [[ $project == *"-uat"* ]]; then
        AMBIENTE="QA"
        echo -e "${YELLOW}Ambiente detectado: QA/UAT${NC}"
    else
        echo -e "${RED}No se pudo detectar el ambiente del proyecto: $project${NC}"
        echo -e "${RED}Se asumirá ambiente QA/UAT${NC}"
        AMBIENTE="QA"
    fi
    
    gcloud container clusters get-credentials $name --zone $region --project $project
    echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} gcloud container clusters get-credentials $name --zone $region --project $project ${WHITE}"
    
    # Crear política de Cloud Armor
    echo -e "${LGRAY}EXEC: ${NC} ${YELLOW} gcloud compute --project=$project security-policies create cve-canary ${WHITE}"
    gcloud compute --project=$project security-policies create cve-canary

    # Regla 1: CVE-Canary (común para todos los ambientes)
    echo -e "${LGRAY}EXEC: ${NC} ${WHITE} Regla 1 - CVE-Canary: deny(403) con descripción${WHITE}"
    gcloud compute --project=$project security-policies rules create 1 \
        --action=deny-403 \
        --security-policy=cve-canary \
        --description="Default CVE Rule valuation" \
        --expression=evaluatePreconfiguredExpr\(\'cve-canary\'\)
    
    # Aplicar reglas según ambiente
    if [ "$AMBIENTE" = "PRO" ]; then
        echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Aplicando reglas para ambiente PRO (3 reglas)${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
        
        # Regla 100: Allowed IPs (PRO) - 7 IPs + 0.0.0.0/0
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} Regla 100 - Allowed IPs: allow (7 IPs + 0.0.0.0/0)${WHITE}"
        gcloud compute --project=$project security-policies rules create 100 \
            --action=allow \
            --security-policy=cve-canary \
            --description="Default rule, higher priority overrides it" \
            --src-ip-ranges=34.123.202.20,34.71.3.13,0.0.0.0/0,189.240.94.226,200.188.18.65,189.240.88.116,200.188.18.66
        
        # Regla 2147483647: Default Deny (PRO)
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} Regla 2147483647 - Default Deny: deny(403) 'Default Deny - All Traffic'${WHITE}"
        gcloud compute --project=$project security-policies rules create 2147483647 \
            --action=deny-403 \
            --security-policy=cve-canary \
            --description="Default Deny - All Traffic" \
            --src-ip-ranges=\*
            
        echo -e "${GREEN}✓ Reglas PRO aplicadas correctamente (3 reglas)${NC}"
            
    else
        echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Aplicando reglas para ambiente QA/UAT (5 reglas)${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
        
        # Regla 90: NAT servicios compartidos (QA/UAT) - 10 IPs
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} Regla 90 - NAT servicios compartidos: allow (10 IPs)${WHITE}"
        gcloud compute --project=$project security-policies rules create 90 \
            --action=allow \
            --security-policy=cve-canary \
            --description="NAT IP addressess on gnp-red-data-central for shared services (eg. Apigee, Nexus, etc.)" \
            --src-ip-ranges=35.223.194.216,34.121.174.67,35.194.4.57,35.223.189.203,35.194.34.199,34.41.162.56,35.225.224.36,34.55.188.137,34.16.70.194,104.197.124.115
        
        # Regla 91: F5 IPs (QA/UAT) - 6 IPs
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} Regla 91 - F5 IPs: allow (6 IPs)${WHITE}"
        gcloud compute --project=$project security-policies rules create 91 \
            --action=allow \
            --security-policy=cve-canary \
            --description="IP addressess related to F5" \
            --src-ip-ranges=34.123.237.82,35.184.162.71,35.238.84.248,34.121.197.40,34.71.3.13,34.123.202.20
        
        # Regla 92: ZSCaler (QA/UAT)
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} Regla 92 - ZSCaler: allow (10.67.126.0/24)${WHITE}"
        gcloud compute --project=$project security-policies rules create 92 \
            --action=allow \
            --security-policy=cve-canary \
            --description="IP segment related to ZSCaler" \
            --src-ip-ranges=10.67.126.0/24
        
        # Regla 2147483647: Default Deny (QA/UAT)
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} Regla 2147483647 - Default Deny: deny(403) 'The Internet'${WHITE}"
        gcloud compute --project=$project security-policies rules create 2147483647 \
            --action=deny-403 \
            --security-policy=cve-canary \
            --description="The Internet" \
            --src-ip-ranges=\*
        
        echo -e "${GREEN}✓ Reglas QA/UAT aplicadas correctamente (5 reglas)${NC}"
    fi

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
