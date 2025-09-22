#!/usr/bin/env python3
"""
Azure Service Principal Setup Script

Creates a complete Azure service principal setup for CI/CD automation:
- App registration with appropriate permissions
- Service principal with client secret
- IAM role assignment for resource management
- Outputs all required environment variables for your CI/CD pipeline

Run this once to set up Azure authentication for automated deployments.
"""

import sys, os, yaml, asyncio
import traceback
from msgraph import GraphServiceClient
from scripts import az_login
from scripts.create import create_app_registration, create_service_principal, create_client_secret, create_iam

def print_status(message, level="info"):
    """Simple console output with different levels"""
    if level == "header":
        print(f"\n{message}")
        print("=" * len(message))
    elif level == "section":
        print(f"\n{message}")
    else:
        print(message)

async def async_main():
    """Main async orchestration function"""

    print_status("Azure Service Principal Setup Process", "header")
    
    print_status("Loading configuration...", "section")
    config = load_config("az_sp_config.yaml")
    az_subscription = config.get("SUBSCRIPTION")
    az_tenant_id = config.get("TENANT_ID")
    print_status("Configuration loaded successfully")
    for key, value in config.items():
        print_status(f"{key}: {value if value is not None else 'Not configured'}")
    
    try:
        print_status("Azure Authentication", "section")

        credential = az_login.azure_login(az_tenant_id)
        
        print_status("Initializing Microsoft Graph Client", "section")
        graph_client = GraphServiceClient(credentials=credential)
        print_status("Graph client initialized successfully")
        
        print_status("App Registration Management", "section")
        app_id = await create_app_registration.create_app_registration_async(
            graph_client=graph_client,
            display_name=config['SP_NAME']
        )
        print_status(f"App Registration complete - App ID: {app_id}")
            
        print_status("Service Principal Management", "section")
        sp_obj_id = await create_service_principal.create_service_principal_async(
            graph_client=graph_client,
            app_id=app_id
        )
        print_status(f"Service Principal complete - Object ID: {sp_obj_id}")
            
        print_status("Client Secret Creation", "section")
        expiry_config = {
            'EXPIRY_YEARS': config.get('EXPIRY_YEARS', 2),
            'EXPIRY_MONTHS': config.get('EXPIRY_MONTHS', 0),
            'EXPIRY_DAYS': config.get('EXPIRY_DAYS', 0)
        }
        client_secret_value = await create_client_secret.create_client_secret_async(
            graph_client=graph_client,
            app_id=app_id,
            secret_name=config['SECRET_NAME'],
            expiry_config=expiry_config
        )
        print_status(f"Client secret created successfully")
        
        print_status("IAM Role Assignment", "section")
        for role in config['ROLES']:
            await create_iam.assign_iam_role_async(
                credential=credential,
                az_subscription=az_subscription,
                sp_obj_id=sp_obj_id,
                role=role,
                scope=f"/subscriptions/{az_subscription}"
            )
        print_status(f"IAM role assignment complete")
        
        print_status("SETUP PROCESS COMPLETED", "header")
        print_status("Your CI/CD Environment Variables:", "section")
        print("-" * 50)
        print_status(f"export AZURE_CLIENT_ID={app_id}")
        print_status(f"export AZURE_CLIENT_SECRET={client_secret_value}")
        print_status(f"export AZURE_TENANT_ID={az_tenant_id}")
        print_status(f"export AZURE_SUBSCRIPTION_ID={az_subscription}")
        print("-" * 50)
            
    except Exception as e:
        print_status(f"ERROR: Setup process failed!", "section")
        print_status(f"   Error details: {str(e)}")
        print_status(f"   Error type: {type(e).__name__}")
                
        print_status(f"Full traceback:", "section")
        
        tb_str = traceback.format_exc()
        for line in tb_str.split('\n'):
            if line.strip():
                print_status(line)
        
        sys.exit(1)

def main():
    """Synchronous main function that runs the async orchestration"""
    asyncio.run(async_main())

def load_config(config_file_path: str) -> dict:
    """Load configuration from environment file"""
    
    if not os.path.exists(config_file_path):
        raise FileNotFoundError(f"Configuration file not found: {config_file_path}")
    
    with open(config_file_path, 'r') as f:
        config = yaml.safe_load(f)
    
    if config is None:
        config = {}
    
    return config

if __name__ == "__main__":
    main()