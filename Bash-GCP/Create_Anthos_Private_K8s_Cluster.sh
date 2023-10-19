#! /bin/bash

function ask() {
    read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
}

echo "GKE  Anthos Cluster Creation V1.05"
echo
echo "Enabling Google Kubernetes Engine API"
gcloud services enable container.googleapis.com
echo
read -r -p "Enter Your GCP Project ID(Default: my-project): " projectid
projectid=${projectid:-my-project}
echo
read -r -p "Enter Your Cluster Name (Default: gke-""$projectid""): " clustername
clustername=${clustername:-gke-"$project-id"}
echo
read -r -p "Enter GCP Region (Default: us-central1): " region
region=${region:-us-central1}
echo
read -r -p "Enter Nodes Machine Type (Default: n1-highmem-4, Options ): " machine_type
machine_type=${machine_type:-n1-standard-2}
echo
read -r -p "Enter Number of nodes (Default: 4): " num_nodes
num_nodes=${num_nodes:-4}
echo
read -r -p "Enter Cluster Release Channel (Default: stable, Options: stable, regular, rapid): " channel
channel=${channel:-stable}

if [[ $channel == rapid ]]; then
    cluster_version="1.27.3-gke.1700"
elif [[ $channel == regular ]]; then
    cluster_version="1.27.3-gke.100"
elif [[ $channel == stable ]]; then
    cluster_version="1.27.3-gke.100"
fi

project_number=$(gcloud projects describe "$projectid" --format="value(projectNumber)")
echo
read -r -p "Enter Node Pool name(Default: default-pool): " node_pool_name
node_pool_name=${node_pool_name:-default-pool}
echo
echo "This cluster configuration is a private cluster and uses shared vpc"
echo "Provide the required shared pvc info"
echo
read -r -p "Enter Control Plane IP Range (Default: 172.19.0.0/28): " control_plane_ip
control_plane_ip=${machine_type:-172.16.0.0/28}
echo
read -r -p "Enter private host network (Default: gnp-datalake-qa): " network
network=${network:-gnp-datalake-qa}
echo
read -r -p "Enter private host subnetwork (Default: my-subnetwork): " subnetwork
network=${network:-"$projectid"}
echo
echo "New Cluster Data"
echo
echo "Project name : $projectid"
echo "Cluster name: $clustername"
echo "Region: $region"
echo "Selected Machine Type: $machine_type"
echo "Number of nodes: $num_nodes"
echo "Selected Release channel: $channel: $cluster_version"
echo "Node Pool Name: $node_pool_name"
echo "Cluster : $cluster_version"
echo "Project Number: $project_number"
echo "Network: $network"
echo "Subnetwork: $subnetwork"
echo "Ip Control Plane Range: $control_plane_ip"
echo
echo "Validando Proyecto"
gcloud config set project "$projectid"
echo
printf " This is going to create a new GKE Cluster Private Cluster With Shared VPC and Anthos Service Mesh"
printf " do you want to proceed?"
ask
echo
echo "Creating Cluster on GCP in project '$projectid'"
echo
gcloud beta container --project "$projectid" clusters create "$clustername" --region "$region" --no-enable-basic-auth --cluster-version "$cluster_version" --release-channel "$channel" --machine-type "$machine_type" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" --max-pods-per-node "110" --num-nodes "$num_nodes" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-private-nodes --enable-private-endpoint --master-ipv4-cidr "$control_plane_ip" --enable-ip-alias --network "projects/gnp-red-data-central/global/networks/""$network""" --subnetwork "projects/gnp-red-data-central/regions/us-central1/subnetworks/""$subnetwork""" --cluster-secondary-range-name "pods" --services-secondary-range-name "servicios" --enable-intra-node-visibility --default-max-pods-per-node "110" --enable-autoscaling --total-min-nodes "4" --total-max-nodes "16" --location-policy "BALANCED" --security-posture=standard --workload-vulnerability-scanning=standard --enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,BackupRestore --enable-autoupgrade --enable-autorepair --max-surge-upgrade 0 --max-unavailable-upgrade 0 --maintenance-window-start "2023-10-02T06:00:00Z" --maintenance-window-end "2023-10-02T16:00:00Z" --maintenance-window-recurrence "FREQ=WEEKLY;BYDAY=SA,SU" --labels mesh_id="proj-$project_number" --binauthz-evaluation-mode​=DISABLED --enable-managed-prometheus --workload-pool "$projectid.svc.id.goog" --enable-shielded-nodes --shielded-secure-boot
echo
echo "Enabling Anthos Service Mesh"
gcloud container fleet mesh enable --project "projectid"
echo
echo "Registering Cluster to Project Fleet"
gcloud container fleet memberships register "$clustername-membership" --gke-cluster="$region"/"$clustername" --enable-workload-identity --project "$projectid"
echo
echo "Provision managed Anthos Service Mesh on the cluster"
gcloud container fleet mesh update --management automatic --memberships "$clustername"-membership --project "$projectid"
echo
sleep 5
echo

echo "Do you want to create a bastion for cluster access? "
ask
echo

service_account=$(gcloud iam service-accounts list --filter="compute@developer.gserviceaccount.com" --project="$projectid" --format="value(email)")
gcloud compute instances create "$projectid-bastion" --project="$projectid" --zone=us-central1-a --machine-type=n1-standard-1 --network-interface=stack-type=IPV4_ONLY,subnet=projects/gnp-red-data-central/regions/us-central1/subnetworks/"$subnetwork",no-address --can-ip-forward --maintenance-policy=MIGRATE --provisioning-model=STANDARD --service-account="$service_account" --scopes=https://www.googleapis.com/auth/cloud-platform --create-disk=auto-delete=yes,boot=yes,device-name="$projectid-bastion",image="projects/debian-cloud/global/images/debian-11-bullseye-v20230912,mode=rw,size=10,type=projects/""$projectid""/zones/us-central1-a/diskTypes/pd-balanced" --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --labels=goog-ec-src=vm_add-gcloud --reservation-affinity=any

#Process variable
#gcloud container clusters describe "$clustername" --region "$zone" | grep publicEndpoint >ext_end_point
#external_ip=$(sed -n 's/^  publicEndpoint: //p' ext_end_point) && rm ext_end_point network_vpc_name
#echo "$external_ip"
#echo
#echo "Creating data-scripts.csv"
#echo "$clustername,https://$external_ip,$clustername,$zone,$projectid" >data-script.csv
#echo
#echo "Verify the data-script.csv contents"
#cat data-script.csv
#echo
#printf "Next step is Cluster Hardening do you want to proceed?"
#ask
#echo
#begin cluster hardening
#echo "Hardening Cluster"
#touch token.txt
#./script-token-all-version-token.sh 2>&1 | tee token.txt
#echo
#./rules-log4j.sh
#echo
#echo "Below you can find token for use on harness"
#cat token.txt
