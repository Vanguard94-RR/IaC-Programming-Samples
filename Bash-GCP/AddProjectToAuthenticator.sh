#!/bin/bash -
#title          :agregar-proyecto-al-autenticador.sh
#description    :Agregar Proyecto al Servicio de Cuentas/Autenticador
#author         :Manuel Cortes
#date           :20230726
#version        :1.0.6
#usage          :./agregar-proyecto-al-autenticador.sh
#notes          :
#bash_version   :5.1.16(1)-release
#============================================================================

# Functions
function ask() {
    read -r -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit 1
}

#Confirmar Proyecto con GCloud
read -r -p "Enter Your GKE Project ID(Default: my-project): " projectid
projectid=${projectid:-my-project}
echo
gcloud config set project "$projectid"

#Confirmar Ambiente
environment="$(echo "$projectid" | sed 's/.*\(...\)/\1/')"
echo "Environment: $environment"
zone="us-central1-a"

#Cambiar al proyecto necesario conforme al ambiente

if [ "$environment" = "pro" ]; then
    project1="gnp-central"
    #echo $project1
else
    project1="gnp-auth"
    #echo $project1

fi
gcloud config set project "$projectid"
if [ "$environment" = "-qa" ]; then
    environment="qa"
else
    echo "$environment"
fi
# Seleccionar una vm del Ambiente

gcloud compute instances list --project="$project1" --filter="auth-ig-$environment" | grep "NAME: " >vms

sed -i 's/NAME: //g' vms
echo
# Seleccionar la ultima VM para conectarse
echo "Available Vm's"
for vm in $(cat vms); do
    echo $vm
done
echo "VM to use $vm"
echo
# Check for previous service account
echo "Check for previous Firebase Service Account"
gcloud iam service-accounts list --project="$projectid" --filter="Firebase" | grep -e "EMAIL" >consulta
ACCOUNT=$(sed -n 's/^EMAIL: //p' consulta)

if [[ -n "$ACCOUNT" ]]; then
    echo "A Firebase Account exist"
    echo "Please do a review of the task"
    exit 1
else
    echo "A Firebase Account does not exist"
    echo "continuing....."
fi
echo
printf " This is going to register the account to project autenticator"
printf " Do you want to proceed?"
ask
# Crear cuenta firebase-jwt
gcloud config set project "$projectid"
echo
echo "Service Account Creation"
gcloud iam service-accounts create firebase-jwt --description="Cuenta de servicio para dar de alta proyecto Autenticador" --display-name="firebase-jwt" --project="$projectid"

gcloud iam service-accounts list --project="$projectid" --filter="firebase" | grep -e "EMAIL" >consulta
ACCOUNT=$(sed -n 's/^EMAIL: //p' consulta)
echo "$ACCOUNT"
echo

# Crear json
echo "Creating Json Key"
sleep 2
gcloud iam service-accounts keys create Firebase-jwt-"$projectid".json --iam-account="$ACCOUNT"
jsonfile=$(ls *.json)
echo

# Copiar el archivo json  a la vm seleccionada
echo "Sending JSON file to the vm"
echo "Do you want to proceed?"
ask
gcloud compute scp "$jsonfile" "$vm": --project "$project1" --tunnel-through-iap --zone="$zone"
echo $jsonfile
echo
# conectarse a la vm

#gcloud compute ssh --zone="$zone" --project="$project1" auth-ig-uat-2nhg --tunnel-through-iap
echo "Performing VM movements"
echo "Do you want to proceed?"
ask
echo "Sending JSON file in to /var/www/sa/ folder"
gcloud compute ssh --zone "$zone" --project "$project1" --tunnel-through-iap "$vm" --command "sudo cp -f "$jsonfile" /var/www/sa/; sudo chown www-data:www-data /var/www/sa/"$jsonfile"; ls -ltr /var/www/sa/*.json|grep Firebase*.json; rm "$jsonfile""
echo
echo "Performing curl "
echo "Do you want to proceed?"
ask
if [ "$environment" = "pro" ]; then
    echo "Sending curl command"
    gcloud compute ssh --zone "$zone" --project "$project1" --tunnel-through-iap "$vm" --command "sudo curl -k http://cuentas.gnp.com.mx/auth/admin/saveProjectInfo?admin_secret=DYGUXoL90n4WtAG9G0huezdGKRFABjV -d @/var/www/sa/"$jsonfile""
    echo
    echo "Done, please validate over the gnp-central Project"
    echo "-->datastore --> default --> Entities -->>Kind=Proyectos-->WHERE=projectid--> == string "$projectid""""
elif [ "$environment" = "uat" ]; then
    echo "Sending curl command"
    gcloud compute ssh --zone "$zone" --project "$project1" --tunnel-through-iap "$vm" --command "sudo curl -k http://cuentas-uat.gnp.com.mx/auth/admin/saveProjectInfo?admin_secret=DYGUXoL90n4WtAG9G0huezdGKRFABjV -d @/var/www/sa/"$jsonfile""
    echo
    echo "Done, please validate over the gnp-auth Project"
    echo "-->datastore --> default --> Entities -->>Kind=Proyectos-->WHERE=projectid--> == string "$projectid""""
else
    echo "Sending curl command"
    gcloud compute ssh --zone "$zone" --project "$project1" --tunnel-through-iap "$vm" --command "sudo curl -k http://cuentas-qa.gnp.com.mx/auth/admin/saveProjectInfo?admin_secret=DYGUXoL90n4WtAG9G0huezdGKRFABjV -d @/var/www/sa/"$jsonfile""
    echo
    echo "Done, please validate over the gnp-auth Project"
    echo "-->datastore --> default --> Entities -->>Kind=Proyectos-->WHERE=projectid--> == string "$projectid""""
fi
echo

echo "Don't forget to copy the .JSON file to GDRive on: "
echo "https://drive.google.com/drive/folders/1BP1-bgBGMswI4lL04nB7HtioacdkWqLJ"

rm consulta
rm vms
