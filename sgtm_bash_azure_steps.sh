#!/bin/bash
#
# Step-by-step commands to deploy server-side Google Tag Manager (sGTM) on Azure Container Apps
# Aligned with sgtm_bash_azure.sh. Run in Azure Cloud Shell (https://shell.azure.com) — use Bash.
# You need the container config string from your server-side GTM container (find it in the container in GTM).
# Run one section at a time and replace placeholder values where indicated.
#

# =============================================================================
# STEP 0: Prerequisites (run these once, especially if using Cloud Shell for the first time)
# =============================================================================
# 1. Open https://shell.azure.com and sign in.
#
# 2. First-time Cloud Shell: when asked to create storage for the shell, choose
#    "Create storage" so your session and files persist.
#
# 3. Register resource providers (required for Container Apps and Log Analytics).
#    Run each command; registration can take a few minutes.
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
#    Wait until both show "Registered" (optional but recommended before continuing):
az provider show -n Microsoft.App --query "registrationState" -o tsv
az provider show -n Microsoft.OperationalInsights --query "registrationState" -o tsv
#
# 4. Optional: set the subscription to use
#    az account set --subscription "<subscription-id>"
#

# =============================================================================
# STEP 1: Set location and derived names (same as script: service name = sgtm-<location>)
# =============================================================================
# Choose your location. Service name will be sgtm-<location>; preview app = sgtm-<location>-view, production = sgtm-<location>-prod.
# Supported locations (or use any valid Azure region):
#   westeurope, northeurope, uksouth, ukwest, germanywestcentral, francecentral, swedencentral, polandcentral,
#   eastus, eastus2, westus, westus2, westus3, centralus, northcentralus, southcentralus, canadacentral, brazilsouth,
#   eastasia, southeastasia, japaneast, japanwest, australiaeast, australiasoutheast, centralindia, southindia,
#   koreacentral, southafricanorth
#
LOCATION="PLACEHOLDER"
RESOURCE_GROUP="rg-sgtm-server"
SERVICE_NAME="sgtm-${LOCATION}"
ENVIRONMENT_NAME="sgtm-env"
LOG_ANALYTICS_WORKSPACE_NAME="sgtm-logs"

# =============================================================================
# STEP 2: Container config string (required)
# =============================================================================
# Paste the config string from your server-side GTM container.
#
CONTAINER_CONFIG='PLACEHOLDER'

# =============================================================================
# STEP 3: Install or upgrade Azure Container Apps CLI extension
# =============================================================================
az extension add --name containerapp --upgrade

# =============================================================================
# STEP 4: Create resource group
# =============================================================================
# Skip if the resource group already exists (script uses ensure_resource_group).
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# =============================================================================
# STEP 5: Create Container Apps environment
# =============================================================================
# Creates Log Analytics workspace "sgtm-logs" and Container Apps environment "sgtm-env".
# Skip this step if the environment already exists (script uses create_environment with existence checks).

az monitor log-analytics workspace create \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LOG_ANALYTICS_WORKSPACE_NAME" \
  --location "$LOCATION"

LOGS_WORKSPACE_ID=$(az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE_NAME" --query customerId --output tsv)
LOGS_WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE_NAME" --query primarySharedKey --output tsv)

az containerapp env create \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --logs-workspace-id "$LOGS_WORKSPACE_ID" \
  --logs-workspace-key "$LOGS_WORKSPACE_KEY"

# =============================================================================
# STEP 6: Deploy PREVIEW (debug) Container App
# =============================================================================
# App name is ${SERVICE_NAME}-view (e.g. sgtm-westeurope-view). Ensure CONTAINER_CONFIG is set (Step 2).

az containerapp create \
  --name "${SERVICE_NAME}-view" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$ENVIRONMENT_NAME" \
  --image "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable" \
  --target-port 8080 \
  --ingress external \
  --min-replicas 0 \
  --max-replicas 1 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars "RUN_AS_PREVIEW_SERVER=true" "CONTAINER_CONFIG=$CONTAINER_CONFIG"

PREVIEW_FQDN=$(az containerapp show \
  --name "${SERVICE_NAME}-view" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn --output tsv)
echo "Preview URL: https://$PREVIEW_FQDN"

# =============================================================================
# STEP 7: Deploy PRODUCTION Container App
# =============================================================================
# App name is ${SERVICE_NAME}-prod. Uses PREVIEW_FQDN from step 6 (preview URL for PREVIEW_SERVER_URL).

az containerapp create \
  --name "${SERVICE_NAME}-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$ENVIRONMENT_NAME" \
  --image "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable" \
  --target-port 8080 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 4 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars "GOOGLE_CLOUD_PROJECT=$RESOURCE_GROUP" "PREVIEW_SERVER_URL=https://$PREVIEW_FQDN" "CONTAINER_CONFIG=$CONTAINER_CONFIG"

# =============================================================================
# STEP 8: Get production URL and verify
# =============================================================================
PROD_FQDN=$(az containerapp show \
  --name "${SERVICE_NAME}-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn --output tsv)

echo "Production URL: https://$PROD_FQDN"
echo "Health check:   https://$PROD_FQDN/healthy"
