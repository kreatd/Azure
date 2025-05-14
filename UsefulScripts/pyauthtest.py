#!/usr/bin/env python3
import msal
import requests

# Define the necessary variables
tenant_id = ""
client_id = ""
client_secret = ""
subscription_id = ""

# Authentication authority URL
authority_url = f"https://login.microsoftonline.us/{tenant_id}"

# Azure Resource Management API endpoint and scope
scope = ["https://management.usgovcloudapi.net/.default"]
resource_url = f"https://management.usgovcloudapi.net/subscriptions/{subscription_id}/providers/Microsoft.Compute/virtualMachines?api-version=2021-03-01"

# Create a confidential client application
app = msal.ConfidentialClientApplication(
    client_id,
    authority=authority_url,
    client_credential=client_secret,
)

# Acquire a token for the confidential client application
result = app.acquire_token_for_client(scopes=scope)

if "access_token" in result:
    access_token = result["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}
    
    # Call the Azure resource management API to list virtual machines
    response = requests.get(resource_url, headers=headers)
    
    if response.status_code == 200:
        vms = response.json()
        print("List of Virtual Machines:")
        for vm in vms["value"]:
            print(f"Name: {vm['name']}, Location: {vm['location']}, Type: {vm['type']}")
    else:
        print(f"Failed to retrieve VMs: {response.status_code} - {response.text}")
else:
    print(f"Failed to acquire token: {result.get('error_description')}")
