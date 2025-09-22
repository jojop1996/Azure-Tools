"""
Azure authentication with automatic fallback from CLI to interactive browser login
"""

from azure.identity import InteractiveBrowserCredential
from azure.core.exceptions import ClientAuthenticationError


def azure_login(az_tenant_id: str):
    """
    Authenticate to Azure using interactive browser.
    Returns credential for use with other Azure services.
    """

    try:
        credential = InteractiveBrowserCredential(tenant_id=az_tenant_id)

        print("   Interactive browser credential created")
        return credential
    except ClientAuthenticationError as e:
        print(f"   Authentication failed: {e}")
        raise
