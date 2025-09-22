"""
Azure IAM role assignment removal using Azure SDK
"""

from azure.mgmt.authorization import AuthorizationManagementClient

async def remove_all_iam_roles_async(credential, graph_client, az_subscription: str, sp_obj_id: str, sp_name: str, role: str, scope: str):
    """
    Comprehensive IAM role assignment removal - handles both direct cleanup and orphaned assignments
    Can work with either object ID or service principal name
    Removes ALL role assignments for the service principal and can also find orphaned assignments
    """
    
    if not sp_obj_id and not sp_name:
        raise ValueError("Either sp_obj_id or sp_name must be provided")
    
    try:
        print(f"   Starting comprehensive IAM role removal...")
        print(f"   Service Principal Object ID: {sp_obj_id if sp_obj_id else 'Not provided'}")
        print(f"   Service Principal Name: {sp_name if sp_name else 'Not provided'}")
        print(f"   Target Role: {role}")
        print(f"   Target Scope: {scope}")
        
        target_sp_ids = []
        
        # If we have object ID, use it directly
        if sp_obj_id:
            target_sp_ids = [sp_obj_id]
            print(f"   Using provided Object ID: {sp_obj_id}")
        else:
            
            print(f"   Searching for service principals with name: {sp_name}")
            service_principals = await graph_client.service_principals.get()
            
            for sp in service_principals.value:
                if sp.display_name == sp_name:
                    target_sp_ids.append(sp.id)
                    print(f"   Found matching service principal - Object ID: {sp.id}")
            
            if not target_sp_ids:
                print(f"   No service principals found with name: {sp_name}")
                print(f"   Checking for role assignments that might reference deleted service principals...")

        # Create Authorization Management client
        print(f"   Initializing Azure Authorization Management client...")
        auth_client = AuthorizationManagementClient(
            credential,
            az_subscription
        )
        print(f"   Authorization client initialized")
        
        # Find ALL role assignments and categorize them
        print(f"   Searching for role assignments...")
        all_assignments = list(auth_client.role_assignments.list_for_subscription())
        
        assignments_to_remove = []
        orphaned_assignments = []
        
        for assignment in all_assignments:
            # Check if assignment belongs to any of our target service principals
            if assignment.principal_id in target_sp_ids:
                assignments_to_remove.append(assignment)
            elif not sp_obj_id and scope and role:
                # Only check for orphaned assignments if we don't have a specific object ID
                # and we have scope/role criteria to match against
                try:
                    # Check if this might be an orphaned assignment by scope/role matching
                    if scope in assignment.scope or assignment.scope in scope:
                        try:
                            role_def = auth_client.role_definitions.get_by_id(assignment.role_definition_id)
                            if role_def.role_name == role:
                                orphaned_assignments.append(assignment)
                        except:
                            pass
                except:
                    pass
        
        total_found = len(assignments_to_remove) + len(orphaned_assignments)
        
        if total_found == 0:
            print(f"   No role assignments found for service principal or orphaned assignments")
            return
        
        print(f"   Found {len(assignments_to_remove)} direct assignment(s) and {len(orphaned_assignments)} potentially orphaned assignment(s)")
        
        # Remove direct assignments
        assignments_removed = 0
        for assignment in assignments_to_remove:
            try:
                # Name used as a default in case the get_by_id method fails (defensive programming)
                role_name = "Unknown"
                try:
                    role_def = auth_client.role_definitions.get_by_id(assignment.role_definition_id)
                    role_name = role_def.role_name
                except:
                    pass
                
                print(f"   - Removing direct assignment - Role: {role_name}, Scope: {assignment.scope}")
                auth_client.role_assignments.delete_by_id(assignment.id)
                print(f"   Direct assignment removed successfully")
                assignments_removed += 1
                
            except Exception as e:
                print(f"   Failed to remove direct assignment {assignment.name}: {str(e)}")
        
        # Remove potentially orphaned assignments
        for assignment in orphaned_assignments:
            try:
                role_name = "Unknown"
                try:
                    role_def = auth_client.role_definitions.get_by_id(assignment.role_definition_id)
                    role_name = role_def.role_name
                except:
                    pass
                
                print(f"   - Found potentially orphaned assignment - Role: {role_name}, Scope: {assignment.scope}")
                print(f"   - Principal ID: {assignment.principal_id}")
                
                # For safety, we'll remove these automatically since this is a destroy script
                auth_client.role_assignments.delete_by_id(assignment.id)
                print(f"   Orphaned assignment removed successfully")
                assignments_removed += 1
                
            except Exception as e:
                print(f"   Failed to remove orphaned assignment {assignment.name}: {str(e)}")
        
        print(f"   Removed {assignments_removed} out of {total_found} role assignment(s)")
        
        if assignments_removed > 0:
            print(f"   IAM role assignment cleanup completed")
        
    except Exception as e:
        print(f"   Failed to remove IAM roles: {str(e)}")
        print(f"   Error type: {type(e).__name__}")
        # Don't raise - continue with other cleanup