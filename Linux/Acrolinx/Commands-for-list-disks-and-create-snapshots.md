manu1331@LAPTOP-U3P21DJ7:~$ az login
A web browser has been opened at https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize. Please continue the login in the web browser. If no web browser is available or if the web browser fails to open, use device code flow with `az login --use-device-code`.
[
{
"cloudName": "AzureCloud",
"homeTenantId": "20ca3e8e-cf43-4f82-9620-febf1f0744e7",
"id": "524e77dd-1069-4c9b-aa6b-e4af0972ff9d",
"isDefault": true,
"managedByTenants": [],
"name": "Acrolinx Azure",
"state": "Enabled",
"tenantId": "20ca3e8e-cf43-4f82-9620-febf1f0744e7",
"user": {
"name": "admin@acrolinxazure.onmicrosoft.com",
"type": "user"
}
}
]
manu1331@LAPTOP-U3P21DJ7:~$ az osDiskId=$(az vm show -g myResourceGroup -n myVM

> ^C
> manu1331@LAPTOP-U3P21DJ7:~$ #az osDiskId=$(az vm show -g myResourceGroup -n myVM --query "storageProfile.osDisk.managedDisk.id -o tsv)
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n microsoft-ce-csi-qa -d
> (ResourceNotFound) The Resource 'Microsoft.Compute/virtualMachines/microsoft-ce-csi-qa' under resource group 'ACROLINX-AZURE-01-WESTUS3' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix
> Code: ResourceNotFound
> Message: The Resource 'Microsoft.Compute/virtualMachines/microsoft-ce-csi-qa' under resource group 'ACROLINX-AZURE-01-WESTUS3' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d
> {
> "additionalCapabilities": null,
> "applicationProfile": null,
> "availabilitySet": null,
> "billingProfile": null,
> "capacityReservation": null,
> "diagnosticsProfile": {

    "bootDiagnostics": {
      "enabled": true,
      "storageUri": null
    }

},
"evictionPolicy": null,
"extendedLocation": null,
"extensionsTimeBudget": null,
"fqdns": "acrolinx-msqa.westus3.cloudapp.azure.com",
"hardwareProfile": {
"vmSize": "Standard_DS4_v2",
"vmSizeProperties": null
},
"host": null,
"hostGroup": null,
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/virtualMachines/AZ-MSWEST-MSQA",
"identity": null,
"licenseType": null,
"location": "westus3",
"macAddresses": "60-45-BD-C7-81-AC",
"name": "AZ-MSWEST-MSQA",
"networkProfile": {
"networkApiVersion": null,
"networkInterfaceConfigurations": null,
"networkInterfaces": [
{
"deleteOption": "Detach",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Network/networkInterfaces/az-mswest-msqa826",
"primary": null,
"resourceGroup": "ACROLINX-AZURE-01-westus3"
}
]
},
"osProfile": null,
"plan": null,
"platformFaultDomain": null,
"powerState": "VM running",
"priority": null,
"privateIps": "10.11.1.8",
"provisioningState": "Succeeded",
"proximityPlacementGroup": null,
"publicIps": "20.168.25.111",
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"resources": null,
"scheduledEventsProfile": null,
"securityProfile": null,
"storageProfile": {
"dataDisks": [
{
"caching": "ReadOnly",
"createOption": "Attach",
"deleteOption": "Detach",
"detachOption": null,
"diskIopsReadWrite": null,
"diskMBpsReadWrite": null,
"diskSizeGb": 100,
"image": null,
"lun": 0,
"managedDisk": {
"diskEncryptionSet": null,
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929",
"resourceGroup": "ACROLINX-AZURE-01-westus3",
"securityProfile": null,
"storageAccountType": "Premium_LRS"
},
"name": "azmswestmsqa-datadisk-000-20221110-181929",
"toBeDetached": false,
"vhd": null,
"writeAcceleratorEnabled": false
},
{
"caching": "ReadOnly",
"createOption": "Attach",
"deleteOption": "Detach",
"detachOption": null,
"diskIopsReadWrite": null,
"diskMBpsReadWrite": null,
"diskSizeGb": 250,
"image": null,
"lun": 1,
"managedDisk": {
"diskEncryptionSet": null,
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929",
"resourceGroup": "ACROLINX-AZURE-01-westus3",
"securityProfile": null,
"storageAccountType": "Premium_LRS"
},
"name": "azmswestmsqa-datadisk-001-20221110-181929",
"toBeDetached": false,
"vhd": null,
"writeAcceleratorEnabled": false
},
{
"caching": "ReadOnly",
"createOption": "Attach",
"deleteOption": "Detach",
"detachOption": null,
"diskIopsReadWrite": null,
"diskMBpsReadWrite": null,
"diskSizeGb": 50,
"image": null,
"lun": 2,
"managedDisk": {
"diskEncryptionSet": null,
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929",
"resourceGroup": "ACROLINX-AZURE-01-westus3",
"securityProfile": null,
"storageAccountType": "Premium_LRS"
},
"name": "azmswestmsqa-datadisk-002-20221110-181929",
"toBeDetached": false,
"vhd": null,
"writeAcceleratorEnabled": false
}
],
"diskControllerType": null,
"imageReference": null,
"osDisk": {
"caching": "ReadWrite",
"createOption": "Attach",
"deleteOption": null,
"diffDiskSettings": null,
"diskSizeGb": 1024,
"encryptionSettings": null,
"image": null,
"managedDisk": {
"diskEncryptionSet": null,
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929",
"resourceGroup": "ACROLINX-AZURE-01-westus3",
"securityProfile": null,
"storageAccountType": "Premium_LRS"
},
"name": "azmswestmsqa-osdisk-20221110-181929",
"osType": "Linux",
"vhd": null,
"writeAcceleratorEnabled": null
}
},
"tags": null,
"timeCreated": "2022-11-04T21:39:16.588503+00:00",
"type": "Microsoft.Compute/virtualMachines",
"userData": null,
"virtualMachineScaleSet": null,
"vmId": "d3cd383b-f95c-419c-b3e0-721d266da718",
"zones": null
}
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.osDisk.managedDisk.id -o tsv

> ^C
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.osDisk.managedDisk.id" -o tsv
> /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.dataDisks.managedDisk.id" -o tsv
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.dataDisks" -o tsv
> ReadOnly Attach Detach None None None 100 None 0 azmswestmsqa-datadisk-000-20221110-181929 False None False
> ReadOnly Attach Detach None None None 250 None 1 azmswestmsqa-datadisk-001-20221110-181929 False None False
> ReadOnly Attach Detach None None None 50 None 2 azmswestmsqa-datadisk-002-20221110-181929 False None False
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.dataDisks.id" -o tsv
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.dataDisks.managedDisks.id" -o tsv
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.dataDisks.managedDisks.id" -o table
> manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile" -o table

manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.\*" -o table
OsType Name Caching CreateOption DiskSizeGb Column1 Column2 Column3

---

Linux azmswestmsqa-osdisk-20221110-181929 ReadWrite Attach 1024
{'lun': 0, 'name': 'azmswestmsqa-datadisk-000-20221110-181929', 'vhd': None, 'image': None, 'caching': 'ReadOnly', 'writeAcceleratorEnabled': False, 'createOption': 'Attach', 'diskSizeGb': 100, 'managedDisk': {'id': '/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929', 'storageAccountType': 'Premium_LRS', 'diskEncryptionSet': None, 'securityProfile': None, 'resourceGroup': 'ACROLINX-AZURE-01-westus3'}, 'toBeDetached': False, 'diskIopsReadWrite': None, 'diskMBpsReadWrite': None, 'detachOption': None, 'deleteOption': 'Detach'} {'lun': 1, 'name': 'azmswestmsqa-datadisk-001-20221110-181929', 'vhd': None, 'image': None, 'caching': 'ReadOnly', 'writeAcceleratorEnabled': False, 'createOption': 'Attach', 'diskSizeGb': 250, 'managedDisk': {'id': '/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929', 'storageAccountType': 'Premium_LRS', 'diskEncryptionSet': None, 'securityProfile': None, 'resourceGroup': 'ACROLINX-AZURE-01-westus3'}, 'toBeDetached': False, 'diskIopsReadWrite': None, 'diskMBpsReadWrite': None, 'detachOption': None, 'deleteOption': 'Detach'} {'lun': 2, 'name': 'azmswestmsqa-datadisk-002-20221110-181929', 'vhd': None, 'image': None, 'caching': 'ReadOnly', 'writeAcceleratorEnabled': False, 'createOption': 'Attach', 'diskSizeGb': 50, 'managedDisk': {'id': '/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929', 'storageAccountType': 'Premium_LRS', 'diskEncryptionSet': None, 'securityProfile': None, 'resourceGroup': 'ACROLINX-AZURE-01-westus3'}, 'toBeDetached': False, 'diskIopsReadWrite': None, 'diskMBpsReadWrite': None, 'detachOption': None, 'deleteOption': 'Detach'}
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.\*" -o tvs
az vm show: 'tvs' is not a valid value for '--output'. Allowed values: json, jsonc, yaml, yamlc, table, tsv, none.

Examples from AI knowledge base:
az vm show --resource-group MyResourceGroup --name MyVm --show-details --output json
Show information about a VM.

https://docs.microsoft.com/en-US/cli/azure/vm#az_vm_show
Read more about the command in reference docs
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.\*" -o tsv
ReadWrite Attach None None 1024 None None azmswestmsqa-osdisk-20221110-181929 Linux None None

manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA --query "storageProfile.dataDisks" -o tsv
ReadOnly Attach Detach None None None 100 None 0 azmswestmsqa-datadisk-000-20221110-181929 False None False
ReadOnly Attach Detach None None None 250 None 1 azmswestmsqa-datadisk-001-20221110-181929 False None False
ReadOnly Attach Detach None None None 50 None 2 azmswestmsqa-datadisk-002-20221110-181929 False None False
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d -o table
Name ResourceGroup PowerState PublicIps Fqdns Location Zones

---

AZ-MSWEST-MSQA ACROLINX-AZURE-01-WESTUS3 VM running 20.168.25.111 acrolinx-msqa.westus3.cloudapp.azure.com westus3
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -o table
Name ResourceGroup Location Zones

---

AZ-MSWEST-MSQA ACROLINX-AZURE-01-WESTUS3 westus3
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d -o table
Name ResourceGroup PowerState PublicIps Fqdns Location Zones

---

AZ-MSWEST-MSQA ACROLINX-AZURE-01-WESTUS3 VM running 20.168.25.111 acrolinx-msqa.westus3.cloudapp.azure.com westus3
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -n AZ-MSWEST-MSQA -d -o table --query
argument --query: expected one argument
To learn more about --query, please visit: 'https://docs.microsoft.com/cli/azure/query-azure-cli'
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -n AZ-MSWEST-MSQA -d -o table
(--resource-group | --ids) are required
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d -o table
Name ResourceGroup PowerState PublicIps Fqdns Location Zones

---

AZ-MSWEST-MSQA ACROLINX-AZURE-01-WESTUS3 VM running 20.168.25.111 acrolinx-msqa.westus3.cloudapp.azure.com westus3
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile[].dataDisks[]' -o table
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile[].dataDisks[*]' -o table
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile.dataDisks[].managedDisk.id' -o table
Result

---

/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile.dataDisks[].managedDisk.id' -o table >>AzureVMDisks
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
Result

---

/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile.dataDisks[].managedDisk.id' -o tsv >>AzureVMDisks
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
Result

---

/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile.dataDisks[].managedDisk.id,storageProfile.osDisk.managedDisk.id' -o tsv >>AzureVMDisks
ERROR: argument --query: invalid jmespath_type value: 'storageProfile.dataDisks[].managedDisk.id,storageProfile.osDisk.managedDisk.id'
To learn more about --query, please visit: 'https://docs.microsoft.com/cli/azure/query-azure-cli'
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
Result

---

/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ rm AzureVMDisks
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].managedDisk.id" -o tsv >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.osDisk.managedDisk.id" -o tsv >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].managedDisk.name" -o tsv >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].managedDisk" -o tsv >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[]" -o tsv >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
ReadOnly Attach Detach None None None 100 None 0 azmswestmsqa-datadisk-000-20221110-181929 False None False
ReadOnly Attach Detach None None None 250 None 1 azmswestmsqa-datadisk-001-20221110-181929 False None False
ReadOnly Attach Detach None None None 50 None 2 azmswestmsqa-datadisk-002-20221110-181929 False None False
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[]" -o table >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
ReadOnly Attach Detach None None None 100 None 0 azmswestmsqa-datadisk-000-20221110-181929 False None False
ReadOnly Attach Detach None None None 250 None 1 azmswestmsqa-datadisk-001-20221110-181929 False None False
ReadOnly Attach Detach None None None 50 None 2 azmswestmsqa-datadisk-002-20221110-181929 False None False
Lun Name Caching WriteAcceleratorEnabled CreateOption DiskSizeGb ToBeDetached DeleteOption

---

0 azmswestmsqa-datadisk-000-20221110-181929 ReadOnly False Attach 100 False Detach
1 azmswestmsqa-datadisk-001-20221110-181929 ReadOnly False Attach 250 False Detach
2 azmswestmsqa-datadisk-002-20221110-181929 ReadOnly False Attach 50 False Detach
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].managedDisk.Name" -o tsv >> AzureVMDisks; cat AzureVMDisks
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929
/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
None /subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-westus3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929 ACROLINX-AZURE-01-westus3 None Premium_LRS
ReadOnly Attach Detach None None None 100 None 0 azmswestmsqa-datadisk-000-20221110-181929 False None False
ReadOnly Attach Detach None None None 250 None 1 azmswestmsqa-datadisk-001-20221110-181929 False None False
ReadOnly Attach Detach None None None 50 None 2 azmswestmsqa-datadisk-002-20221110-181929 False None False
Lun Name Caching WriteAcceleratorEnabled CreateOption DiskSizeGb ToBeDetached DeleteOption

---

0 azmswestmsqa-datadisk-000-20221110-181929 ReadOnly False Attach 100 False Detach
1 azmswestmsqa-datadisk-001-20221110-181929 ReadOnly False Attach 250 False Detach
2 azmswestmsqa-datadisk-002-20221110-181929 ReadOnly False Attach 50 False Detach
manu1331@LAPTOP-U3P21DJ7:~$ rm -rf AzureVMDisks
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].managedDisk.Name" -o tsv >> AzureVMDisks; cat AzureVMDisks
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].Name" -o tsv >> AzureVMDisks; cat AzureVMDisks
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.dataDisks[].name" -o tsv >> AzureVMDisks; cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.osDisks[].name" -o tsv >> AzureVMDisks; cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.osDisk[].name" -o tsv >> AzureVMDisks; cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.osDisk.name" -o tsv >> AzureVMDisks; cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-datadisk-000-20221110-181929 --name CHG0269084-osDisk-backup-11-11-2022
{
"completionPercent": null,
"copyCompletionError": null,
"creationData": {
"createOption": "Copy",
"galleryImageReference": null,
"imageReference": null,
"logicalSectorSize": null,
"securityDataUri": null,
"sourceResourceId": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929",
"sourceUniqueId": "f15a6a75-b934-4824-a375-e49c38067ec1",
"sourceUri": null,
"storageAccountId": null,
"uploadSizeBytes": null
},
"dataAccessAuthMode": null,
"diskAccessId": null,
"diskSizeBytes": 107374182400,
"diskSizeGb": 100,
"diskState": "Unattached",
"encryption": {
"diskEncryptionSetId": null,
"type": "EncryptionAtRestWithPlatformKey"
},
"encryptionSettingsCollection": null,
"extendedLocation": null,
"hyperVGeneration": "V1",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/snapshots/CHG0269084-osDisk-backup-11-11-2022",
"incremental": false,
"location": "westus3",
"managedBy": null,
"name": "CHG0269084-osDisk-backup-11-11-2022",
"networkAccessPolicy": "AllowAll",
"osType": null,
"provisioningState": "Succeeded",
"publicNetworkAccess": "Enabled",
"purchasePlan": null,
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"securityProfile": null,
"sku": {
"name": "Standard_LRS",
"tier": "Standard"
},
"supportedCapabilities": null,
"supportsHibernation": null,
"tags": {},
"timeCreated": "2022-11-12T00:37:04.278238+00:00",
"type": "Microsoft.Compute/snapshots",
"uniqueId": "9c52a39c-33d5-4b6e-89f5-2151c9d5b05e"
}
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query "storageProfile.osDisk.name" -o tsv >> AzureVMDisks; cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
azmswestmsqa-osdisk-20221110-181929
azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-datadisk-000-20221110-181929 --name CHG0269084-datadisk-000-backup-11-11-2022
{
"completionPercent": null,
"copyCompletionError": null,
"creationData": {
"createOption": "Copy",
"galleryImageReference": null,
"imageReference": null,
"logicalSectorSize": null,
"securityDataUri": null,
"sourceResourceId": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929",
"sourceUniqueId": "f15a6a75-b934-4824-a375-e49c38067ec1",
"sourceUri": null,
"storageAccountId": null,
"uploadSizeBytes": null
},
"dataAccessAuthMode": null,
"diskAccessId": null,
"diskSizeBytes": 107374182400,
"diskSizeGb": 100,
"diskState": "Unattached",
"encryption": {
"diskEncryptionSetId": null,
"type": "EncryptionAtRestWithPlatformKey"
},
"encryptionSettingsCollection": null,
"extendedLocation": null,
"hyperVGeneration": "V1",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/snapshots/CHG0269084-datadisk-000-backup-11-11-2022",
"incremental": false,
"location": "westus3",
"managedBy": null,
"name": "CHG0269084-datadisk-000-backup-11-11-2022",
"networkAccessPolicy": "AllowAll",
"osType": null,
"provisioningState": "Succeeded",
"publicNetworkAccess": "Enabled",
"purchasePlan": null,
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"securityProfile": null,
"sku": {
"name": "Standard_LRS",
"tier": "Standard"
},
"supportedCapabilities": null,
"supportsHibernation": null,
"tags": {},
"timeCreated": "2022-11-12T00:40:23.420720+00:00",
"type": "Microsoft.Compute/snapshots",
"uniqueId": "ffd2059b-39a9-41cc-a929-a4c18b42083c"
}
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
azmswestmsqa-osdisk-20221110-181929
azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ #az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-datadisk-001-20221110-181929 --name CHG0269084-datadisk-001-backup-11-11-2022
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot delete -g ACROLINX-AZURE-01-WESTUS3 --name CHG0269084-datadisk-001-backup-11-11-2022
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot delete -g ACROLINX-AZURE-01-WESTUS3 --name CHG0269084-datadisk-000-backup-11-11-2022
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot delete -g ACROLINX-AZURE-01-WESTUS3 --name CHG0269084-osDisk-backup-11-11-2022
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-datadisk-000-20221110-181929 --name CHG0269084-AZ-MSWEST-MSQA-datadisk-000-backup-11-11-2022
{
"completionPercent": null,
"copyCompletionError": null,
"creationData": {
"createOption": "Copy",
"galleryImageReference": null,
"imageReference": null,
"logicalSectorSize": null,
"securityDataUri": null,
"sourceResourceId": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-000-20221110-181929",
"sourceUniqueId": "f15a6a75-b934-4824-a375-e49c38067ec1",
"sourceUri": null,
"storageAccountId": null,
"uploadSizeBytes": null
},
"dataAccessAuthMode": null,
"diskAccessId": null,
"diskSizeBytes": 107374182400,
"diskSizeGb": 100,
"diskState": "Unattached",
"encryption": {
"diskEncryptionSetId": null,
"type": "EncryptionAtRestWithPlatformKey"
},
"encryptionSettingsCollection": null,
"extendedLocation": null,
"hyperVGeneration": "V1",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/snapshots/CHG0269084-AZ-MSWEST-MSQA-datadisk-000-backup-11-11-2022",
"incremental": false,
"location": "westus3",
"managedBy": null,
"name": "CHG0269084-AZ-MSWEST-MSQA-datadisk-000-backup-11-11-2022",
"networkAccessPolicy": "AllowAll",
"osType": null,
"provisioningState": "Succeeded",
"publicNetworkAccess": "Enabled",
"purchasePlan": null,
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"securityProfile": null,
"sku": {
"name": "Standard_LRS",
"tier": "Standard"
},
"supportedCapabilities": null,
"supportsHibernation": null,
"tags": {},
"timeCreated": "2022-11-12T00:54:22.401632+00:00",
"type": "Microsoft.Compute/snapshots",
"uniqueId": "807f2e2d-fa6e-4a24-91a7-0a7398dda1e7"
}
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
azmswestmsqa-osdisk-20221110-181929
azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-datadisk-001-20221110-181929 --name CHG0269084-AZ-MSWEST-MSQA-datadisk-001-backup-11-11-2022
{
"completionPercent": null,
"copyCompletionError": null,
"creationData": {
"createOption": "Copy",
"galleryImageReference": null,
"imageReference": null,
"logicalSectorSize": null,
"securityDataUri": null,
"sourceResourceId": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-001-20221110-181929",
"sourceUniqueId": "b93c1b18-8153-48f2-a3f1-aba63ea69ff5",
"sourceUri": null,
"storageAccountId": null,
"uploadSizeBytes": null
},
"dataAccessAuthMode": null,
"diskAccessId": null,
"diskSizeBytes": 268435456000,
"diskSizeGb": 250,
"diskState": "Unattached",
"encryption": {
"diskEncryptionSetId": null,
"type": "EncryptionAtRestWithPlatformKey"
},
"encryptionSettingsCollection": null,
"extendedLocation": null,
"hyperVGeneration": "V1",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/snapshots/CHG0269084-AZ-MSWEST-MSQA-datadisk-001-backup-11-11-2022",
"incremental": false,
"location": "westus3",
"managedBy": null,
"name": "CHG0269084-AZ-MSWEST-MSQA-datadisk-001-backup-11-11-2022",
"networkAccessPolicy": "AllowAll",
"osType": null,
"provisioningState": "Succeeded",
"publicNetworkAccess": "Enabled",
"purchasePlan": null,
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"securityProfile": null,
"sku": {
"name": "Standard_LRS",
"tier": "Standard"
},
"supportedCapabilities": null,
"supportsHibernation": null,
"tags": {},
"timeCreated": "2022-11-12T00:55:03.370820+00:00",
"type": "Microsoft.Compute/snapshots",
"uniqueId": "574cac91-43a2-4fae-b0c8-028b5b379eda"
}
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
azmswestmsqa-osdisk-20221110-181929
azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-datadisk-002-20221110-181929 --name CHG0269084-AZ-MSWEST-MSQA-datadisk-002-backup-11-11-2022
{
"completionPercent": null,
"copyCompletionError": null,
"creationData": {
"createOption": "Copy",
"galleryImageReference": null,
"imageReference": null,
"logicalSectorSize": null,
"securityDataUri": null,
"sourceResourceId": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/disks/azmswestmsqa-datadisk-002-20221110-181929",
"sourceUniqueId": "6ff538af-b918-4caa-936d-996cb0efb973",
"sourceUri": null,
"storageAccountId": null,
"uploadSizeBytes": null
},
"dataAccessAuthMode": null,
"diskAccessId": null,
"diskSizeBytes": 53687091200,
"diskSizeGb": 50,
"diskState": "Unattached",
"encryption": {
"diskEncryptionSetId": null,
"type": "EncryptionAtRestWithPlatformKey"
},
"encryptionSettingsCollection": null,
"extendedLocation": null,
"hyperVGeneration": "V1",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/snapshots/CHG0269084-AZ-MSWEST-MSQA-datadisk-002-backup-11-11-2022",
"incremental": false,
"location": "westus3",
"managedBy": null,
"name": "CHG0269084-AZ-MSWEST-MSQA-datadisk-002-backup-11-11-2022",
"networkAccessPolicy": "AllowAll",
"osType": null,
"provisioningState": "Succeeded",
"publicNetworkAccess": "Enabled",
"purchasePlan": null,
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"securityProfile": null,
"sku": {
"name": "Standard_LRS",
"tier": "Standard"
},
"supportedCapabilities": null,
"supportsHibernation": null,
"tags": {},
"timeCreated": "2022-11-12T00:57:07.934350+00:00",
"type": "Microsoft.Compute/snapshots",
"uniqueId": "d362dfbc-445a-4fd3-a343-6db8ff8ee18a"
}
manu1331@LAPTOP-U3P21DJ7:~$ cat AzureVMDisks
azmswestmsqa-datadisk-000-20221110-181929
azmswestmsqa-datadisk-001-20221110-181929
azmswestmsqa-datadisk-002-20221110-181929
azmswestmsqa-osdisk-20221110-181929
azmswestmsqa-osdisk-20221110-181929
manu1331@LAPTOP-U3P21DJ7:~$ az snapshot create -g ACROLINX-AZURE-01-WESTUS3 --source azmswestmsqa-osdisk-20221110-181929 --name CHG0269084-AZ-MSWEST-MSQA-osdisk-backup-11-11-2022
{
"completionPercent": null,
"copyCompletionError": null,
"creationData": {
"createOption": "Copy",
"galleryImageReference": null,
"imageReference": null,
"logicalSectorSize": null,
"securityDataUri": null,
"sourceResourceId": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/disks/azmswestmsqa-osdisk-20221110-181929",
"sourceUniqueId": "e6ae35c9-965e-45a2-864a-8887cccc24d2",
"sourceUri": null,
"storageAccountId": null,
"uploadSizeBytes": null
},
"dataAccessAuthMode": null,
"diskAccessId": null,
"diskSizeBytes": 1099511627776,
"diskSizeGb": 1024,
"diskState": "Unattached",
"encryption": {
"diskEncryptionSetId": null,
"type": "EncryptionAtRestWithPlatformKey"
},
"encryptionSettingsCollection": null,
"extendedLocation": null,
"hyperVGeneration": "V1",
"id": "/subscriptions/524e77dd-1069-4c9b-aa6b-e4af0972ff9d/resourceGroups/ACROLINX-AZURE-01-WESTUS3/providers/Microsoft.Compute/snapshots/CHG0269084-AZ-MSWEST-MSQA-osdisk-backup-11-11-2022",
"incremental": false,
"location": "westus3",
"managedBy": null,
"name": "CHG0269084-AZ-MSWEST-MSQA-osdisk-backup-11-11-2022",
"networkAccessPolicy": "AllowAll",
"osType": "Linux",
"provisioningState": "Succeeded",
"publicNetworkAccess": "Enabled",
"purchasePlan": null,
"resourceGroup": "ACROLINX-AZURE-01-WESTUS3",
"securityProfile": null,
"sku": {
"name": "Standard_LRS",
"tier": "Standard"
},
"supportedCapabilities": null,
"supportsHibernation": null,
"tags": {},
"timeCreated": "2022-11-12T00:57:53.012985+00:00",
"type": "Microsoft.Compute/snapshots",
"uniqueId": "95a704ad-c31a-4d9a-a2ef-e73e3d596d4f"
}
manu1331@LAPTOP-U3P21DJ7:~$ az logout
manu1331@LAPTOP-U3P21DJ7:~$ az vm show -g ACROLINX-AZURE-01-WESTUS3 -n AZ-MSWEST-MSQA -d --query 'storageProfile[].dataDisks[]' -o table
Please run 'az login' to setup account.
manu1331@LAPTOP-U3P21DJ7:~$
