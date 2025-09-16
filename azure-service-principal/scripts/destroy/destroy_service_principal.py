"""
Azure Service Principal removal using Microsoft Graph SDK
"""

async def remove_service_principal_async(graph_client, sp_obj_id: str):
    """
    Remove a service principal using Microsoft Graph SDK
    """
    
    try:
        print(f"   Removing service principal with Object ID '{sp_obj_id}'...")
        
        # Get service principal details first
        try:
            sp_details = await graph_client.service_principals.by_service_principal_id(sp_obj_id).get()
            print(f"   Found service principal: {sp_details.display_name}")
        except Exception as e:
            print(f"   Service principal not found or already removed: {str(e)}")
            return
        
        # Delete the service principal
        print(f"   Deleting service principal...")
        await graph_client.service_principals.by_service_principal_id(sp_obj_id).delete()
        
        print(f"   Service principal removed successfully")
        print(f"   Removed Object ID: {sp_obj_id}")
        print(f"   Display Name: {sp_details.display_name}")
        
    except Exception as e:
        print(f"   Failed to remove service principal: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        # Don't raise - continue with other cleanup