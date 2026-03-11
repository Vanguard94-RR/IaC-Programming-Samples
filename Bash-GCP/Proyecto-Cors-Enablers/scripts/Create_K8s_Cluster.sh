#! /bin/bash

function checker() {
    touch cluster-status
    while true; do
        cluster_status=$(gcloud container clusters describe "$clustername" --zone "$zone" | grep "status:") >cluster-status
        sed -i '/ status: RUNNING/d' cluster-status
        cluster_status=$(<"cluster-status")
        printf "%s\n" "$cluster_status"
        if [ "$cluster_status" == 'status: RUNNING' ]; then
            return 1

        else
            sleep 10
        fi
        rm -rf cluster-status
    done
}

function pause() {
    reard -r -r -n 1 -p "
    Press any key to continue ..."
    echo ""
}

function ask() {
    read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
}

external_ip="192.168.1.18"

echo "GKE Cluster Creation V1.04"
echo
echo "Enabling Google Kubernetes Engine API"
gcloud services enable container.googleapis.com
echo
read -r -p "Enter Your GKE Project ID(Default: my-project): " projectid
projectid=${projectid:-my-project}
echo
read -r -p "Enter Your Cluster Name (Default: gke-my-cluster): " clustername
clustername=${clustername:-gke-my-cluster}
echo
read -r -p "Enter GCP Region (Default: us-central1): " region
region=${region:-us-central1}
echo
read -r -p "Enter GCP Zone (Default: us-central1-f, Options: us-central1-a): " zone
zone=${zone:-us-central1-f}
echo
read -r -p "Enter Nodes Machine Type (Default: n1-standard-2, Options ): " machine_type
machine_type=${machine_type:-n1-standard-2}
echo
read -r -p "Enter Number of nodes (Default: 3): " num_nodes
num_nodes=${num_nodes:-3}
echo
read -r -p "Enter Cluster Release Channel (Default: regular, Options: stable, regular, rapid): " channel
channel=${channel:-regular}

if [[ $channel == rapid ]]; then
    cluster_version="1.27.2-gke.2100"
elif [[ $channel == regular ]]; then
    cluster_version="1.26.5-gke.1200"
elif [[ $channel == stable ]]; then
    cluster_version="1.27.2-gke.1200"
fi

echo "$cluster_version"
echo
read -r -p "Enter Node Pool name(Default: default-pool): "
node_pool_name=${node_pool_name:-default-pool}
echo
echo "New Cluster Data"
echo
echo "Project name : $projectid"
echo "Cluster name: $clustername"
echo "Region: $region"
echo "Zone: $zone"
echo "Selected Machine Type: $machine_type"
echo "Number of nodes: $num_nodes"
echo "Selected Release channel: $channel: $cluster_version"
echo "$node_pool_name"
echo
echo "Validando Proyecto"
gcloud config set project "$projectid"
echo
echo "Validando VPC"
gcloud compute networks list | grep NAME >network_vpc_name
vpc_name=$(sed -n 's/^NAME: //p' network_vpc_name)

if [[ -z "$vpc_name" ]]; then
    echo "No VPC $vpc_name Assigned"
    printf " This is going to create a VPC and Subnet"
    printf " Do you want to proceed?"
    read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1

    read -r -p "Enter VPC IP Range in format : 'xxx.xxx.xxx.xxx/xx": vpc_ip
    echo
    gcloud compute networks create "$projectid" --project="$projectid" --subnet-mode=custom --mtu=1460 --bgp-routing-mode=regional
    echo
    gcloud compute networks subnets create "$projectid" --project="$projectid" --range="$vpc_ip" --stack-type=IPV4_ONLY --network="$projectid" --region="$region" --enable-private-ip-google-access

else
    echo "VPC is:   $vpc_name"
fi
echo "Creating Cluster on GCP in project $projectid $zone"
echo
printf " This is going to create a new GKE Cluster"
printf " do you want to proceed?"
read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
echo

gcloud beta container --project "$projectid" clusters create "$clustername" --zone "$zone" --no-enable-basic-auth --release-channel "$channel" --cluster-version "$cluster_version" --machine-type "n1-standard-2" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" --num-nodes "$num_nodes" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/$projectid/global/networks/$projectid" --subnetwork "projects/$projectid/regions/$region/subnetworks/$projectid" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --security-posture=standard --workload-vulnerability-scanning=standard --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,BackupRestore --enable-autoupgrade --enable-autorepair --max-surge-upgrade 0 --max-unavailable-upgrade 0 --autoscaling-profile optimize-utilization --enable-managed-prometheus --enable-shielded-nodes --shielded-secure-boot --shielded-integrity-monitoring --node-locations "$zone" --workload-pool "$projectid".svc.id.goog --workload-metadata GKE_METADATA

sleep 5
echo
# Updating Node Pool
echo "Updating  Node Pool"
gcloud container node-pools update "$node_pool_name" --cluster "$clustername" --zone "$zone" --enable-blue-green-upgrade
sleep 5
echo
gcloud container node-pools update "$node_pool_name" --cluster "$clustername" --zone "$zone" --enable-private-nodes
sleep 10
echo
echo "Getting relevant data"

#Process variable
gcloud container clusters describe "$clustername" --region "$region" | grep publicEndpoint >ext_end_point
external_ip=$(sed -n 's/^  publicEndpoint: //p' ext_end_point) && rm ext_end_point network_vpc_name
echo "$external_ip"

echo "Creating data-scripts.csv"
echo "$clustername,https://$external_ip,$clustername,$zone,$projectid" >data-script.csv
echo
echo "Verify the data-script.csv contents"
cat data-script.csv
echo
printf "Netx step is Cluster Hardening do you want to proceed?"
read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
echo
#begin cluster hardening
echo "Hardening Cluster"
touch token.txt
./script-token-all-version-token.sh 2>&1 | tee token.txt
echo
./rules-log4j.sh
echo
echo "Below you can find token for use on harness"
cat token.txt
