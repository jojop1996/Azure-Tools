"""
Azure IAM role assignment using Azure SDK
"""

from azure.mgmt.authorization import AuthorizationManagementClient
from azure.mgmt.authorization.models import RoleAssignmentCreateParameters
from uuid import uuid4

async def assign_iam_role_async(credential, az_subscription: str, sp_obj_id: str, role: str, scope: str):
    """
    Assign an IAM role to the service principal
    """
    
    try:
        print(f"   Starting IAM role assignment for service principal...")
        print(f"   Service Principal Object ID: {sp_obj_id}")
        print(f"   Role: {role}")
        print(f"   Scope: {scope}")
        
        # Create Authorization Management client
        print(f"   Initializing Azure Authorization Management client...")
        auth_client = AuthorizationManagementClient(
            credential,
            az_subscription
        )
        print(f"   Authorization client initialized")
        
        # Get role definition
        print(f"   Looking up role definition for '{role}'...")
        role_definitions = list(auth_client.role_definitions.list(
            scope,
            filter=f"roleName eq '{role}'"
        ))
        
        if not role_definitions:
            print(f"   Role '{role}' not found in scope '{scope}'")
            raise Exception(f"Role '{role}' not found")
        
        role_definition_id = role_definitions[0].id
        print(f"   Found role definition ID: {role_definition_id}")
        
        # Check if role assignment already exists
        print(f"   Checking for existing role assignments...")
        existing_assignments = list(auth_client.role_assignments.list_for_scope(scope))
        for assignment in existing_assignments:
            if (assignment.principal_id == sp_obj_id and 
                assignment.role_definition_id == role_definition_id):
                print(f"   Role assignment already exists")
                print(f"   Assignment ID: {assignment.id}")
                return
        
        # Create role assignment
        print(f"   Role assignment not found, creating new one...")
        print(f"   Preparing role assignment parameters...")
        role_assignment_params = RoleAssignmentCreateParameters(
            role_definition_id=role_definition_id,
            principal_id=sp_obj_id,
            principal_type="ServicePrincipal"
        )
        
        # Generate a unique name for the role assignment
        role_assignment_name = str(uuid4())
        print(f"   Generated assignment name: {role_assignment_name}")
        
        print(f"   Creating role assignment...")
        role_assignment = auth_client.role_assignments.create(
            scope,
            role_assignment_name,
            role_assignment_params
        )
        
        print(f"   Role assignment created successfully")
        print(f"   Assignment ID: {role_assignment.id}")
        print(f"   Role: {role}")
        print(f"   Principal: {sp_obj_id}")
        print(f"   Scope: {scope}")
        
    except Exception as e:
        print(f"   Failed to assign IAM role: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        raise