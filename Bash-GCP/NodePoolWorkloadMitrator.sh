#! /bin/bash

function ask() {
    read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
}

echo "GKE NodePool Migration"
echo
read -r -p "Enter Your GKE Project ID(Default: my-project): " projectid
projectid=${projectid:-my-project}
echo
read -r -p "Enter Your Cluster Name (Default: gke-my-cluster): " clustername
clustername=${clustername:-gke-my-cluster}
echo
read -r -p "Enter old Node-Pool Name (Default: default-pool): " oldpool
oldpool=${oldpool:-default-pool}
echo
read -r -p "Enter new Node-Pool Name (Default: ""$clustername""-pool): " newpool
newpool=${newpool:-$clustername-pool}
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
read -r -p "New Node-Pool shall have private nodes? (Default: yes): " private_nodes
private_nodes=${private_nodes:-yes}
echo
#Create log file
#touch "NodePoolMigration.log"
echo "Set project"
gcloud config set project $projectid
echo
gcloud container clusters get-credentials $clustername --zone "$zone" --project "$projectid" #>> NodePoolMigration.log
echo
echo "Create and update new Node-Pool"
echo

if [[ $private_nodes == yes ]]; then
    gcloud beta container --project $projectid node-pools create $newpool --cluster $clustername --zone "us-central1-f" --node-version "1.26.6-gke.1700" --machine-type $machine_type --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" --num-nodes $num_nodes --enable-autoupgrade --enable-autorepair --max-surge-upgrade 0 --max-unavailable-upgrade 0 --shielded-secure-boot --enable-blue-green-upgrade --enable-private-nodes --shielded-integrity-monitoring
elif [[ $private_nodes == no ]]; then
    gcloud beta container --project $projectid node-pools create $newpool --cluster $clustername --zone "us-central1-f" --node-version "1.26.6-gke.1700" --machine-type $machine_type --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" --num-nodes $num_nodes --enable-autoupgrade --enable-autorepair --max-surge-upgrade 0 --max-unavailable-upgrade 0 --shielded-secure-boot --enable-blue-green-upgrade --shielded-integrity-monitoring
else
    echo "Please choose if nodepool should have private nodes"
    exit
fi

echo
sleep 5
echo "Updating  Node Pool"
gcloud container node-pools update $newpool --cluster "$clustername" --zone "$zone" --enable-blue-green-upgrade
sleep 5
echo
echo "The next actions will migrate the workloads to the new nodes, continue? :"
ask
echo "Cordon previous node-pool?"
ask
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool -o=name); do kubectl cordon "$node" && sleep 5; done
echo
sleep 5
echo
echo "Evict all pods with a 10 sec grace period, continue?: "
ask
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$oldpool -o=name); do kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node"; done
echo
sleep 5
echo " Rezise Old node pool to 0 nodes"
ask
gcloud container clusters resize $clustername --node-pool $oldpool --num-nodes 0 --region us-central1-f
echo
echo "On Cloud console validate that all workloads get status Ready in new nodes"
echo
#while [[ $(kubectl get pods -A -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do sleep 1 && kubectl get pods -A && sleep 5 && clear; done
echo
