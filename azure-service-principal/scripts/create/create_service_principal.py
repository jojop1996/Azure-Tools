"""
Azure Service Principal creation using Microsoft Graph SDK
"""

from msgraph.generated.models.service_principal import ServicePrincipal

async def create_service_principal_async(graph_client, app_id: str) -> str:
    """
    Create a service principal linked to an app registration using Microsoft Graph SDK
    Returns the service principal object ID
    """
    
    try:
        # Check if service principal already exists
        print(f"   Checking if service principal for app ID '{app_id}' already exists...")
        print(f"   Querying Microsoft Graph for existing service principals...")
        service_principals = await graph_client.service_principals.get()
        print(f"   Found {len(service_principals.value)} existing service principals")
        
        for sp in service_principals.value:
            if sp.app_id == app_id:
                print(f"   Service principal already exists")
                print(f"   Existing Object ID: {sp.id}")
                print(f"   Display Name: {sp.display_name}")
                return sp.id
        
        print(f"   Service principal for app ID '{app_id}' not found, creating new one...")
        
        # Create service principal object
        print(f"   Preparing service principal object for app ID: {app_id}")
        service_principal = ServicePrincipal()
        service_principal.app_id = app_id
        service_principal.account_enabled = True
        
        # Create the service principal
        print(f"   Submitting service principal creation to Microsoft Graph...")
        created_sp = await graph_client.service_principals.post(service_principal)
        sp_obj_id = created_sp.id
        
        print(f"   Service principal created successfully")
        print(f"   New Object ID: {sp_obj_id}")
        print(f"   Display Name: {created_sp.display_name}")
        return sp_obj_id
            
    except Exception as e:
        print(f"   Failed to create service principal: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        raise