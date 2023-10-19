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

"name,ip,token" >cluster.csv

while read -r name ip cluster region project; do
    echo "name : $name"
    echo "ip   : $ip"
    echo "cluster : $cluster"
    echo "region  : $region"
    echo "project : $project"
    echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} gcloud container clusters get-credentials $name --zone $region --project $project"
    gcloud container clusters get-credentials "$name" --zone "$region" --project "$project"
    kubectl -n kube-system create serviceaccount harness-key
    kubectl create clusterrolebinding harness-key-binding --clusterrole=cluster-admin --serviceaccount=kube-system:harness-key
    TOKENNAME=$(kubectl -n kube-system get serviceaccount/harness-key -o jsonpath='{.secrets[0].name}')
    if [ -z "$TOKENNAME" ]; then
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} creating token ..."
        echo "apiVersion: v1" >secret.yaml
        echo "kind: Secret" >>secret.yaml
        echo "metadata:" >>secret.yaml
        echo "  name: harness-key-token" >>secret.yaml
        echo "  annotations:" >>secret.yaml
        echo "    kubernetes.io/service-account.name: harness-key" >>secret.yaml
        echo "type: kubernetes.io/service-account-token" >>secret.yaml
        sleep 1
        echo -e "${LGRAY}EXEC: ${NC} ${LGREEN} kubectl apply -f secret.yaml -n kube-system"
        kubectl apply -f secret.yaml -n kube-system
        sleep 1
        TOKEN=$(kubectl -n kube-system get secret harness-key-token -o jsonpath='{.data.token}' | base64 --decode)
        echo -e "${LGRAY}OUT : ${NC} ${WHITE} $name,$ip,$TOKEN"
        sleep 1
    else
        TOKEN=$(kubectl -n kube-system get secret "$TOKENNAME" -o jsonpath='{.data.token}' | base64 --decode)
    fi
    echo -e "${LGRAY}OUT : ${NC} ${WHITE} $name,$ip,$TOKEN"
    echo "$name-$project,$ip,$TOKEN" >>cluster.csv
    sleep 1
done <$INPUT
IFS=$OLDIFS
