#!/bin/bash
#Filename       :suscriptions.sh
#description    :This script will make subscriptions that never expire from a txt file.
#author         :Manuel Cortes
#date           :20230811
#version        :0.1
#usage          :bash suscriptions.sh
#notes          :Install Vim and Emacs to use this script.
#bash_version   :4.1.5(1)-release
#==============================================================================

for i in $(cat topics.txt); do
    #echo $i

    name=$(echo $i | cut -d '.' -f 3)
    #echo $name

    topic=$(grep $i topics.txt)
    sus=$(grep $name sus.txt)

    echo "Suscription - ${sus}"
    echo "Topic - ${topic}"

    gcloud pubsub subscriptions create $sus --topic=$topic --expiration-period=never

done
