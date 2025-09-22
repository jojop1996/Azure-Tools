#!/usr/bin/env python3
"""
Azure Service Principal Cleanup Script

Safely removes all Azure resources created by az_create_sp.py including:
- IAM role assignments
- Service principals
- App registrations
- Handles orphaned resources if service principals were partially deleted

Run this to clean up when you no longer need the CI/CD service principal.
CAUTION: This will permanently delete Azure resources and require confirmation.
"""

import sys, os, yaml, asyncio
import traceback
from msgraph import GraphServiceClient
from scripts import az_login
from scripts.destroy import (
    destroy_iam,
    destroy_service_principal,
    destroy_app_registration,
)


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
    """Main async destruction function"""

    print_status("Azure Service Principal Destruction Process", "header")

    print_status("Loading configuration...", "section")
    config = load_config("az_sp_config.yaml")
    az_tenant_id = config.get("TENANT_ID")
    az_subscription = config.get("SUBSCRIPTION")
    print_status("Configuration loaded successfully")
    for key, value in config.items():
        print_status(f"{key}: {value if value is not None else 'Not configured'}")

    # Confirmation prompt
    print_status("WARNING: This will destroy Azure resources!", "section")
    response = input("Are you sure you want to continue? (yes/no): ")
    if response.lower() not in ["yes", "y"]:
        print_status("Destruction cancelled by user")
        return

    try:
        print_status("Azure Authentication", "section")
        credential = az_login.azure_login(az_tenant_id)
        print_status(f"Authenticated to tenant: {az_tenant_id}")

        print_status("Initializing Microsoft Graph Client", "section")
        graph_client = GraphServiceClient(credentials=credential)
        print_status("Graph client initialized successfully")

        # Get app registration info first (needed for other deletions)
        print_status("Finding App Registration", "section")
        applications = await graph_client.applications.get()
        app_id = None
        app_object_id = None
        sp_obj_id = None

        for app in applications.value:
            if app.display_name == config["SP_NAME"]:
                app_id = app.app_id
                app_object_id = app.id
                print_status(f"Found App Registration - App ID: {app_id}")
                break

        if not app_id:
            print_status(
                f"App registration '{config['SP_NAME']}' not found - will check for orphaned resources"
            )

        # Get service principal info
        if app_id:
            service_principals = await graph_client.service_principals.get()
            for sp in service_principals.value:
                if sp.app_id == app_id:
                    sp_obj_id = sp.id
                    print_status(f"Found Service Principal - Object ID: {sp_obj_id}")
                    break

        # Destroy in reverse order of creation

        # Attempt to clean up IAM role assignments (including orphaned ones)
        print_status("IAM Role Assignment Removal", "section")
        for role in config['ROLES']:
            await destroy_iam.remove_all_iam_roles_async(
                credential=credential,
                az_subscription=az_subscription,
                graph_client=graph_client,
                sp_obj_id=sp_obj_id,
                sp_name=config['SP_NAME'],
                role=role,
                scope=f"/subscriptions/{az_subscription}"
            )
        print_status("IAM role removal complete")

        if sp_obj_id:
            print_status("Service Principal Removal", "section")
            await destroy_service_principal.remove_service_principal_async(
                graph_client=graph_client, sp_obj_id=sp_obj_id
            )
            print_status("Service principal removal complete")

        if app_object_id:
            print_status("App Registration Removal", "section")
            await destroy_app_registration.remove_app_registration_async(
                graph_client=graph_client, app_object_id=app_object_id
            )
            print_status("App registration removal complete")

        print_status("DESTRUCTION PROCESS COMPLETED", "header")
        print_status("All resources have been successfully removed")

    except Exception as e:
        print_status(f"ERROR: Destruction process failed!", "section")
        print_status(f"   Error details: {str(e)}")
        print_status(f"   Error type: {type(e).__name__}")
        print_status(f"Full traceback:", "section")

        tb_str = traceback.format_exc()
        for line in tb_str.split("\n"):
            if line.strip():
                print_status(line)

        sys.exit(1)


def main():
    """Synchronous main function that runs the async destruction"""
    asyncio.run(async_main())


def load_config(config_file_path: str) -> dict:
    """Load configuration from environment file"""

    if not os.path.exists(config_file_path):
        raise FileNotFoundError(f"Configuration file not found: {config_file_path}")

    with open(config_file_path, "r") as f:
        config = yaml.safe_load(f)

    if config is None:
        config = {}

    return config


if __name__ == "__main__":
    main()
