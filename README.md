# Server-side GTM on Azure Container Apps — Bash script

Deploy [server-side Google Tag Manager](https://developers.google.com/tag-platform/tag-manager/server-side) (sGTM) on **Microsoft Azure Container Apps** using a single interactive Bash script.

## What it does

- Registers required Azure resource providers (Microsoft.App, Microsoft.OperationalInsights)
- Prompts for **location** (list or custom) and **container config string** from your sGTM container
- Creates resource group, Log Analytics workspace, and Container Apps environment
- Deploys **preview** (`sgtm-<location>-view`) and **production** (`sgtm-<location>-prod`) apps
- Uses the official GTM container image; production gets a free managed SSL-capable URL

## Prerequisites

- **Azure subscription**
- **Container config string** from your server-side GTM container (GTM → Container → copy config)
- Run in **Azure Cloud Shell** with **Bash**: [shell.azure.com](https://shell.azure.com)

## How to run

1. Open [Azure Cloud Shell](https://shell.azure.com) and select **Bash**.
2. Run the script from this repository:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/selnekovic/sgtm-bash-script-azure/main/sgtm_bash_azure.sh)"
```

3. Choose **location** (number or name) and enter your **container config string** when prompted.
4. Confirm to create resources and deploy. When finished, the script prints the production URL and health-check URL.

## License and credits

**MIT License.** The script is released under the MIT License.


