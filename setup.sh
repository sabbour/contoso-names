#!/bin/bash

# Parameters
RANDOMSTRING=$(mktemp --dry-run XXXXX | tr '[:upper:]' '[:lower:]')
PREFIX=contoso

echo -e "Location (default: westus): \c"
read LOCATION
LOCATION="${LOCATION:=westus}"
echo $LOCATION

echo -e "Resource group (default: ${PREFIX}${RANDOMSTRING}-rg): \c"
read CLUSTER_RG
CLUSTER_RG="${CLUSTER_RG:=${PREFIX}${RANDOMSTRING}-rg}"
echo $CLUSTER_RG

CLUSTER_NAME=${PREFIX}${RANDOMSTRING}
ACR_NAME=${PREFIX}${RANDOMSTRING}
ACR_RG=${CLUSTER_RG}
KV_NAME=${PREFIX}${RANDOMSTRING}
KV_RG=${CLUSTER_RG}

echo -e "Root Azure DNS name (default: ${RANDOMSTRING}.contoso.com): \c"
read AZUREDNS_NAME
AZUREDNS_NAME="${AZUREDNS_NAME:=${RANDOMSTRING}.contoso.com}"
echo $AZUREDNS_NAME

echo -e "Root Azure DNS resource group (default: ${CLUSTER_RG}): \c"
read AZUREDNS_RG
AZUREDNS_RG="${AZUREDNS_RG:=${CLUSTER_RG}}"
echo $AZUREDNS_RG

echo -e "Application subdomain name (default: namesapp): \c"
read SUBDOMAIN
SUBDOMAIN="${SUBDOMAIN:=namesapp}"
echo $SUBDOMAIN

CERTIFICATE_NAME=${RANDOMSTRING}-wild
AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "========================================================"
echo "|            ABOUT TO RUN THE SETUP SCRIPT             |"
echo "========================================================"
echo ""
echo "Will execute against subscription: ${AZURE_SUBSCRIPTION_ID}"
echo "Continue? Type y or Y."
read REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit
fi

echo "========================================================"
echo "|                    STARTING SETUP                    |"
echo "========================================================"
echo ""

START="$(date +%s)"
# Make sure the KEDA Preview feature is registered
echo "Making sure that the features are registered"
az extension add --upgrade --name aks-preview
az feature register --name AKS-KedaPreview --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerService

# Create resource group
echo "Creating resource group ${CLUSTER_RG} in ${LOCATION}"
az group create -n ${CLUSTER_RG} -l ${LOCATION}

# Checking if Azure DNS Zone exists
echo "Checking if the root Azure DNS Zone ${AZUREDNS_NAME} exists in resource group ${AZUREDNS_RG}"
AZUREDNS_NAME_CHECK=$(az network dns zone list -o tsv --query "[?name=='${AZUREDNS_NAME}'].name")
if [[ ! -z ${AZUREDNS_NAME_CHECK}  ]];
then
    echo "..DNS Zone exists, skipping create"
else
    echo "..DNS Zone does not exist"
    # Create Azure DNS Zone
    echo "Creating Azure DNS zone ${AZUREDNS_NAME}"
    az network dns zone create -n ${AZUREDNS_NAME} -g ${AZUREDNS_RG}        
fi


echo "Retrieving the resource ID for the Azure DNS zone"
AZUREDNS_RESOURCEID=$(az network dns zone show -n ${AZUREDNS_NAME} -g ${AZUREDNS_RG} --query id -o tsv)

# Create an Azure Key Vault
echo "Creating Azure Key Vault ${KV_NAME}"
az keyvault create -n ${KV_NAME} -g ${KV_RG}

# Create a self signed certificate on Azure Key Vault using the policy template
echo "Creating a self-signed certificate on the Key Vault for ${SUBDOMAIN}.${AZUREDNS_NAME} and *.${SUBDOMAIN}.${AZUREDNS_NAME}"
sed "s/DOMAIN/${SUBDOMAIN}.${AZUREDNS_NAME}/" kv_cert_policy_template.json > generated-cert-policies/${CERTIFICATE_NAME}_kv_policy.json
az keyvault certificate create --vault-name ${KV_NAME} -n ${CERTIFICATE_NAME} -p @generated-cert-policies/${CERTIFICATE_NAME}_kv_policy.json

# Create Azure Container Registry
echo "Creating an Azure Container Registry ${ACR_NAME}"
az acr create -n ${ACR_NAME} -g ${ACR_RG} -l ${LOCATION} --sku Basic

# Create AKS cluster attached to the registry and activate Web App Routing, Key Vault CSI, OSM, Monitoring
echo "Creating an Azure Kubernetes Service cluster ${CLUSTER_NAME}"
az aks create -n ${CLUSTER_NAME} -g ${CLUSTER_RG} --node-count 3 --generate-ssh-keys \
--enable-addons azure-keyvault-secrets-provider,open-service-mesh,web_application_routing,monitoring \
--enable-managed-identity \
--enable-msi-auth-for-monitoring \
--enable-secret-rotation \
--enable-cluster-autoscaler \
--min-count 3 \
--max-count 6 \
--node-vm-size Standard_DS4_v2 \
--attach-acr ${ACR_NAME}

# Retrieve the user managed identity object ID for the Web App Routing add-on
echo "Retrieving the managed identity for the Web Application Routing add-on"
CLUSTER_RESOURCE_ID=$(az aks show -n ${CLUSTER_NAME} -g ${CLUSTER_RG} --query id -o tsv)
SUBSCRIPTION_ID=$(awk '{ sub(/.*subscriptions\//, ""); sub(/\/resourcegroups.*/, ""); print }' <<< "$CLUSTER_RESOURCE_ID")
MANAGEDIDENTITYNAME="webapprouting-${CLUSTER_NAME}"
NODERESOURCEGROUP=$(az aks show -n ${CLUSTER_NAME} -g ${CLUSTER_RG} --query nodeResourceGroup -o tsv)
USERMANAGEDIDENTITY_RESOURCEID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${NODERESOURCEGROUP}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${MANAGEDIDENTITYNAME}"
MANAGEDIDENTITY_OBJECTID=$(az resource show --id $USERMANAGEDIDENTITY_RESOURCEID --query "properties.principalId" -o tsv | tr -d '[:space:]')

# Grant the Web App Routing add-on certificate read access on the Key Vault
echo "Granting the Web Application Routing add-on certificate read access on the Key Vault"
az keyvault set-policy --name $KV_NAME --object-id $MANAGEDIDENTITY_OBJECTID --secret-permissions get --certificate-permissions get

# Grant the Web App Routing add-on Contributor prmissions on the Azure DNS zone
echo "Granting the Web Application Routing add-on Contributor access on the Azure DNS zone"
az role assignment create --role "DNS Zone Contributor" --assignee ${MANAGEDIDENTITY_OBJECTID} --scope ${AZUREDNS_RESOURCEID}

# Update the Web App Routing add-on to use Azure DNS
echo "Updating the Web Application Routing add-on to use the Azure DNS zone"
az aks addon update -n ${CLUSTER_NAME} -g ${CLUSTER_RG} \
--addon web_application_routing \
--dns-zone-resource-id=${AZUREDNS_RESOURCEID}

# Retrieve AKS cluster credentials
echo "Retrieving the Azure Kubernetes Service cluster credentials"
az aks get-credentials -n ${CLUSTER_NAME} -g ${CLUSTER_RG}

END="$(date +%s)"
DURATION=$[ ${END} - ${START} ]

echo ""
echo "========================================================"
echo "|                   SETUP COMPLETED                    |"
echo "========================================================"
echo ""
echo "Total time elapsed: $(( DURATION / 60 )) minutes"
echo ""
echo "========================================================"
echo "|                   DNS ZONE SETTINGS                  |"
echo "========================================================"
echo ""
echo "Make sure that your DNS has been updated to properly resolve ${AZUREDNS_NAME}"
echo "Use ${SUBDOMAIN}.${AZUREDNS_NAME} when configuring the ingress hostname."
echo ""
echo "Here are the DNS NS records you should set in your parent DNS zone or hosts file:"
az network dns zone show --name ${AZUREDNS_NAME} --resource-group ${AZUREDNS_RG} --query nameServers  -o tsv
echo ""
echo "========================================================"
echo "|               KEYVAULT CERFIFICATE                   |"
echo "========================================================"
echo ""
echo "Use the following certificate URL when configuring the ingress for ${SUBDOMAIN}.${AZUREDNS_NAME}"
az keyvault certificate show --vault-name ${KV_NAME} -n ${CERTIFICATE_NAME} --query "id" --output tsv
echo ""
echo "========================================================"
echo "|               CLEAN UP AFTER YOU ARE DONE            |"
echo "========================================================"
echo ""
echo "Delete the ${CLUSTER_RG} resource group when you are done by running:"
echo "az group delete --name ${CLUSTER_RG}"
echo ""
echo "Have fun!"