"""
Azure App Registration removal using Microsoft Graph SDK
"""

async def remove_app_registration_async(graph_client, app_object_id: str):
    """
    Remove an Azure AD app registration using Microsoft Graph SDK
    """
    
    try:
        print(f"   Removing app registration with Object ID '{app_object_id}'...")
        
        # Get app registration details first
        try:
            app_details = await graph_client.applications.by_application_id(app_object_id).get()
            print(f"   Found app registration: {app_details.display_name}")
            print(f"   App ID: {app_details.app_id}")
        except Exception as e:
            print(f"   App registration not found or already removed: {str(e)}")
            return
        
        # Delete the app registration
        print(f"   Deleting app registration...")
        await graph_client.applications.by_application_id(app_object_id).delete()
        
        print(f"   App registration removed successfully")
        print(f"   Removed Object ID: {app_object_id}")
        print(f"   App ID: {app_details.app_id}")
        print(f"   Display Name: {app_details.display_name}")
        
    except Exception as e:
        print(f"   Failed to remove app registration: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        # Don't raise - continue with other cleanup