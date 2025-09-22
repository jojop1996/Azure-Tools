# Azure Service Principal Setup

This directory contains Python scripts to automate the creation and management of a single Azure service principal for CI/CD deployments.

## Files Structure

```
az_identity_setup/
├── az_create_sp.py           # Create service principal
├── az_destroy_sp.py          # Remove service principal
├── az_sp_config.yaml         # Configuration file
├── requirements.txt          # Python dependencies
├── scripts/                  # Helper modules
└── README.md                 # This file
```

## Quick Start

### 1. Create a Virtual Environment
```bash
python3 -m venv venv
```

### 2. Activate the Virtual Environment
Activate the virtual environment:
```bash
source venv/bin/activate
```

### 3. Install Dependencies
```bash
pip install -r requirements.txt
```

### 4. Create Service Principal
```bash
python az_create_sp.py
```

### 5. Use Output Credentials
The script outputs credentials for use in your IaC deployments:
```bash
Your CI/CD Environment Variables:
--------------------------------------------------
AZURE_CLIENT_ID       = <client-id>
AZURE_CLIENT_SECRET   = <client-secret>
AZURE_TENANT_ID       = <tenant-id>
AZURE_SUBSCRIPTION_ID = <subscription-id>
--------------------------------------------------
```

## Configuration

Edit `az_sp_config.yaml` to customize:

| Parameter | Description |
|-----------|-------------|
| `SP_NAME` | Service principal name |
| `ROLES` | Azure role to assign (e.g., Contributor, Reader, Owner) |
| `SUBSCRIPTION` | Azure subscription ID where resources will be created |
| `TENANT_ID` | Azure Active Directory tenant ID |
| `SECRET_NAME` | Name for the client secret credential |
| `EXPIRY_YEARS` `EXPIRY_MONTHS` `EXPIRY_DAYS` | Secret expiration (default 2 years) |

## Cleanup

Remove the service principal and all associated resources:
```bash
python az_destroy_sp.py
```
