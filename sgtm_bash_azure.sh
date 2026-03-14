#!/bin/bash
# Server-side Google Tag Manager on Microsoft Azure (Container Apps)
# Script by Julius Selnekovic | selnekovic.com
#
# MIT License
#
# Copyright (c) 2026 Julius Selnekovic
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

DOCKER_IMAGE_URL="gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable"
WELCOME_MESSAGE="""Set up your tagging server on Azure Container Apps. Running..."""

LOCATIONS=(
  "westeurope"
  "northeurope"
  "uksouth"
  "ukwest"
  "germanywestcentral"
  "francecentral"
  "swedencentral"
  "polandcentral"
  "eastus"
  "eastus2"
  "westus"
  "westus2"
  "westus3"
  "centralus"
  "northcentralus"
  "southcentralus"
  "canadacentral"
  "brazilsouth"
  "eastasia"
  "southeastasia"
  "japaneast"
  "japanwest"
  "australiaeast"
  "australiasoutheast"
  "centralindia"
  "southindia"
  "koreacentral"
  "southafricanorth"
)

trap "exit" INT
set -e

# Register resource providers (required for Container Apps and Log Analytics).
register_resource_providers() {
  echo "Registering resource providers (Microsoft.App, Microsoft.OperationalInsights)..."
  az provider register --namespace Microsoft.App
  az provider register --namespace Microsoft.OperationalInsights
  echo "Waiting for registration..."
  while true; do
    APP_STATE=$(az provider show -n Microsoft.App --query "registrationState" -o tsv 2>/dev/null || echo "Pending")
    OPS_STATE=$(az provider show -n Microsoft.OperationalInsights --query "registrationState" -o tsv 2>/dev/null || echo "Pending")
    echo "  Microsoft.App: $APP_STATE, Microsoft.OperationalInsights: $OPS_STATE"
    if [[ "$APP_STATE" == "Registered" && "$OPS_STATE" == "Registered" ]]; then
      break
    fi
    sleep 10
  done
  echo "Resource providers registered."
}

# Ask user to enter the container config string (required). Find it in your server-side GTM container.
set_container_configuration() {
  while [[ -z "${container_configuration}" ]]; do
    echo "Container config string (Required): "
    read -r container_configuration

    if [[ "${container_configuration}" == 'null' ]]; then
      echo "Container config cannot be 'null'."
      container_configuration=""
    fi
  done
}

# Set Azure settings (predefined).
set_azure_settings() {
  resource_group="rg-sgtm-server"
  set_location
  service_name="sgtm-${location}"
  environment_name="sgtm-env"
  log_analytics_workspace_name="sgtm-logs"
}

# Show list of locations; user chooses by number or enters a custom value (required).
set_location() {
  while [[ -z "${location}" ]]; do
    echo "Location (choose number 1-${#LOCATIONS[@]} or enter custom value):"
    for i in "${!LOCATIONS[@]}"; do
      echo "  $((i + 1))) ${LOCATIONS[$i]}"
    done
    echo "  Or type a custom location:"
    read -r location_choice
    if [[ -z "$location_choice" ]]; then
      echo "Location is required."
      continue
    fi
    if [[ "$location_choice" =~ ^[0-9]+$ ]] && ((location_choice >= 1 && location_choice <= ${#LOCATIONS[@]})); then
      location="${LOCATIONS[$((location_choice - 1))]}"
    else
      location="$location_choice"
    fi
  done
}

# Prompt for confirmation; user must type yes or no.
confirmation() {
  while true; do
    echo "$1"
    read -r confirmation
    confirmation="$(echo "${confirmation}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${confirmation}" == "yes" ]]; then
      break
    fi
    if [[ "${confirmation}" == "no" ]]; then
      exit 0
    fi
    echo "Please type yes or no."
  done
}


# Create resource group if it does not exist.
ensure_resource_group() {
  if ! az group show --name "${resource_group}" &>/dev/null; then
    echo "Creating resource group: ${resource_group}"
    az group create --name "${resource_group}" --location "${location}"
  fi
}


# Create Container Apps environment and optional Log Analytics workspace.
create_environment() {
  if ! az containerapp env show --name "${environment_name}" --resource-group "${resource_group}" &>/dev/null; then
    echo "Creating Container Apps environment: ${environment_name}"
    if [[ -n "${log_analytics_workspace_name}" ]]; then
      if ! az monitor log-analytics workspace show --resource-group "${resource_group}" --workspace-name "${log_analytics_workspace_name}" &>/dev/null; then
        echo "Creating Log Analytics workspace: ${log_analytics_workspace_name}"
        az monitor log-analytics workspace create \
          --resource-group "${resource_group}" \
          --workspace-name "${log_analytics_workspace_name}" \
          --location "${location}"
      fi
      LOGS_WORKSPACE_ID=$(az monitor log-analytics workspace show --resource-group "${resource_group}" --workspace-name "${log_analytics_workspace_name}" --query customerId --output tsv)
      LOGS_WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group "${resource_group}" --workspace-name "${log_analytics_workspace_name}" --query primarySharedKey --output tsv)
      az containerapp env create \
        --name "${environment_name}" \
        --resource-group "${resource_group}" \
        --location "${location}" \
        --logs-workspace-id "${LOGS_WORKSPACE_ID}" \
        --logs-workspace-key "${LOGS_WORKSPACE_KEY}"
    else
      az containerapp env create \
        --name "${environment_name}" \
        --resource-group "${resource_group}" \
        --location "${location}"
    fi
  fi
}


# Deploy preview (debug) Container App 
deploy_preview_app() {
  echo ""
  echo "Deploying preview (debug) Container App..."
  if ! az containerapp env show --name "${environment_name}" --resource-group "${resource_group}" &>/dev/null; then
    echo "ERROR: Container Apps environment '${environment_name}' not found in resource group '${resource_group}'."
    echo "Ensure the environment was created (check for errors above) and that you are in the correct subscription."
    exit 1
  fi
  preview_app_name="${service_name}-view"

  debug_service_url=$(az containerapp create \
    --name "${preview_app_name}" \
    --resource-group "${resource_group}" \
    --environment "${environment_name}" \
    --image "${DOCKER_IMAGE_URL}" \
    --target-port 8080 \
    --ingress external \
    --min-replicas 0 \
    --max-replicas 1 \
    --cpu 0.25 \
    --memory 0.5Gi \
    --env-vars "RUN_AS_PREVIEW_SERVER=true" "CONTAINER_CONFIG=${container_configuration}" \
    --query properties.configuration.ingress.fqdn \
    --output tsv)
}

# Deploy production Container App 
deploy_production_app() {
  echo ""
  echo "Deploying production Container App..."
  production_app_name="${service_name}-prod"

  production_service_url=$(az containerapp create \
    --name "${production_app_name}" \
    --resource-group "${resource_group}" \
    --environment "${environment_name}" \
    --image "${DOCKER_IMAGE_URL}" \
    --target-port 8080 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 4 \
    --cpu 0.5 \
    --memory 1.0Gi \
    --env-vars "GOOGLE_CLOUD_PROJECT=${resource_group}" "PREVIEW_SERVER_URL=https://${debug_service_url}" "CONTAINER_CONFIG=${container_configuration}" \
    --query properties.configuration.ingress.fqdn \
    --output tsv)
}

# Main execution
echo "${WELCOME_MESSAGE}"

# Ensure Azure CLI Container Apps extension
az extension add --name containerapp --upgrade 2>/dev/null || true

# Ensure Azure CLI Container Apps extension (needed for provider registration and deploy).
az extension add --name containerapp --upgrade 2>/dev/null || true

# Register resource providers first (required for Container Apps and Log Analytics).
register_resource_providers

echo ""
# Ask for location, then container config. Service name = sgtm-server-<location>.
set_azure_settings
set_container_configuration

# Show summary and ask for confirmation.
echo ""
echo "Your configured settings are:"
echo "  Service Name:    ${service_name}"
echo "  Resource Group:  ${resource_group}"
echo "  Location:       ${location}"
echo "  Environment:    ${environment_name}"
echo "  Log Analytics workspace: ${log_analytics_workspace_name:-<auto>}"
config_preview="${container_configuration:0:80}"
[[ ${#container_configuration} -gt 80 ]] && config_preview="${config_preview}..."
echo "  Container config string: ${config_preview}"
echo ""
confirmation "Do you wish to continue? (yes/no): "
echo "Let's try it..."

# Create Azure resources and deploy preview and production apps.
ensure_resource_group
create_environment
deploy_preview_app
deploy_production_app

# Final output
echo ""
echo "Deployment is complete."
echo "Production server: https://${production_service_url}"
echo "Production health check: https://${production_service_url}/healthy"
exit 0
