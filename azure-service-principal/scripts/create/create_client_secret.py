"""
Azure client secret creation using Microsoft Graph SDK
"""

from msgraph.generated.models.password_credential import PasswordCredential
from datetime import datetime, timedelta
from dateutil.relativedelta import relativedelta

async def create_client_secret_async(graph_client, app_id: str, secret_name: str, expiry_config: dict) -> str:
    """
    Create a client secret for the app registration using Microsoft Graph SDK
    
    Args:
        graph_client: Microsoft Graph client instance
        app_id: Application ID for the app registration
        secret_name: Display name for the client secret
        expiry_config: Dict containing EXPIRY_YEARS, EXPIRY_MONTHS, EXPIRY_DAYS
    
    Returns:
        The client secret value
    """
    
    try:
        print(f"   Creating client secret '{secret_name}' for app ID '{app_id}'...")
        
        # Get the application object ID from app ID
        print(f"   Looking up application object ID from app ID...")
        applications = await graph_client.applications.get()
        app_object_id = None
        
        # Check for matching application object ID
        for app in applications.value:
            if app.app_id == app_id:
                app_object_id = app.id
                print(f"   Found application object ID: {app_object_id}")
                break
        
        if not app_object_id:
            raise Exception(f"Application with ID {app_id} not found")
        
        # Check for existing secrets - skip creation if ANY exist
        print(f"   Checking for existing client secrets...")
        try:
            app_details = await graph_client.applications.by_application_id(app_object_id).get()
            existing_secrets = app_details.password_credentials or []
            
            if existing_secrets:
                print(f"   Found {len(existing_secrets)} existing client secrets")
                print(f"   Skipping secret creation - using existing secret")
                print(f"   Note: Cannot retrieve existing secret value, ensure you have it saved")
                # Return a placeholder since we can't retrieve the actual value
                return "[EXISTING_SECRET_VALUE_NOT_RETRIEVABLE]"
            
            print(f"   No existing secrets found, proceeding with new secret creation...")
            
        except Exception as e:
            print(f"   Could not check existing secrets: {str(e)}")
            print(f"   Proceeding with secret creation...")
        
        # Create password credential (client secret)
        print(f"   Preparing password credential...")
        end_date = datetime.now() + relativedelta(
            years=expiry_config.get('EXPIRY_YEARS', 2),
            months=expiry_config.get('EXPIRY_MONTHS', 0),
            days=expiry_config.get('EXPIRY_DAYS', 0)
        )
        print(f"   Secret expiration date: {end_date.isoformat()}")
        
        password_credential = PasswordCredential()
        password_credential.display_name = secret_name
        password_credential.end_date_time = end_date
        
        # Add the password credential to the application
        print(f"   Submitting client secret creation to Microsoft Graph...")
        created_secret = await graph_client.applications.by_application_id(app_object_id).add_password.post(password_credential)
        
        # Capture the newly created client secret
        client_secret_value = created_secret.secret_text
        
        print("   Client secret created successfully")
        print(f"   Secret name: {secret_name}")
        print(f"   Secret ID: {created_secret.key_id}")
        return client_secret_value
        
    except Exception as e:
        print(f"   Failed to create client secret: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        raise