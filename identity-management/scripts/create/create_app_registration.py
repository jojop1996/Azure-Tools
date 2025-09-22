"""
Azure App Registration creation using Microsoft Graph SDK
"""

from msgraph.generated.models.application import Application

async def create_app_registration_async(graph_client, display_name: str) -> str:
    """
    Create an Azure AD app registration using Microsoft Graph SDK
    Returns the application ID
    """
    
    try:
        # Check if app registration already exists
        print(f"   Checking if app registration '{display_name}' already exists...")
        print(f"   Querying Microsoft Graph for existing applications...")
        applications = await graph_client.applications.get()
        print(f"   Found {len(applications.value)} existing applications")
        
        for app in applications.value:
            if app.display_name == display_name:
                print(f"   App registration '{display_name}' already exists")
                print(f"   Existing App ID: {app.app_id}")
                print(f"   Existing Object ID: {app.id}")
                return app.app_id
        
        print(f"   App registration '{display_name}' not found, creating new one...")
        
        # Create application object
        print(f"   Preparing application object with display name: {display_name}")
        application = Application()
        application.display_name = display_name
        
        # Create the application
        print(f"   Submitting app registration to Microsoft Graph...")
        created_app = await graph_client.applications.post(application)
        app_id = created_app.app_id
        
        print(f"   App registration created successfully")
        print(f"   New App ID: {app_id}")
        print(f"   New Object ID: {created_app.id}")
        return app_id
        
    except Exception as e:
        print(f"   Failed to create app registration: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        raise