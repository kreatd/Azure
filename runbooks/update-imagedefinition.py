#!/usr/bin/env python3
from azure.identity import ManagedIdentityCredential
import requests  

def get_token(scope, authority):
    credential = ManagedIdentityCredential(authority=authority)
    token = credential.get_token(scope)
    return token.token

#splits version strings into tuples of integers
def version_key(version):
    return tuple(map(int, version.split('.')))

#get latest image version for {gallery_image_name}
def get_latest_image_version(subscription_id, gallery_resource_group, gallery_name, gallery_image_name, token):
    
    #url for grabbing all versions
    get_url = f"https://management.usgovcloudapi.net/subscriptions/{subscription_id}/resourceGroups/{gallery_resource_group}/providers/Microsoft.Compute/galleries/{gallery_name}/images/{gallery_image_name}/versions?api-version=2023-07-03"
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    
    #parse response, get image versions
    response = requests.get(get_url, headers=headers)
    image_versions = response.json().get('value', [])

    #Pull most recent version
    sorted_versions = sorted(image_versions, key=lambda x: version_key(x['name']))
    latest_version = sorted_versions[-1]
    return latest_version['name']

#increment gallery image version number to create a new latest image
def increment_version(version: str) -> str:
    #Split the string into msjor,  minor and patch.
    major, minor, patch = map(int, version.split('.'))

    #increment patch by 1
    patch += 1

    #check if patch needs to roll over to minor.
    if patch > 99:
        patch = 0
        minor += 1

    #check if minor needs to roll over to major.
    if minor > 99:
        minor = 0
        major += 1

    # create new version of the string
    new_version = f"{major}.{minor}.{patch}"
    return new_version

def create_image_definition_version(subscription_id, vm_resource_group, vm_name, location, gallery_image_name, gallery_name, gallery_image_version_name, gallery_resource_group, token):
    
    url = f"https://management.usgovcloudapi.net/subscriptions/{subscription_id}/resourceGroups/{gallery_resource_group}/providers/Microsoft.Compute/galleries/{gallery_name}/images/{gallery_image_name}/versions/{gallery_image_version_name}?api-version=2023-07-03"

    #json body for gallery image version creation
    body = {
        "location": "usgovtexas",
        "properties": {
            "publishingProfile": {
            "targetRegions": [
                {
                "name": f"{location}",
                "regionalReplicaCount": 1
                }
            ]
            },
            "storageProfile": {
            "source": {
                "virtualMachineId": f"/subscriptions/{subscription_id}/resourceGroups/{vm_resource_group}/providers/Microsoft.Compute/virtualMachines/{vm_name}"
            }
            }
        }
    }

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    response = requests.put(url, headers=headers, json=body)

    if response.status_code == 200 or response.status_code == 201:
        print(f"Image version '{gallery_image_version_name}' created successfully from VM '{vm_name}'")
    else:
        print(f"Failed to create Image: {response.status_code}, {response.text}")
    

if __name__ == "__main__":
    #set params
    subscription_id = ""
    vm_resource_group = ""
    gallery_resource_group = ""
    vm_name = ""
    location = ""
    gallery_image_name = ""
    gallery_name = ""
    authority="https://login.microsoftonline.us"
    scope =""

    #get token
    token = get_token(scope, authority)
    
    #get latest version
    latest_version = get_latest_image_version(subscription_id, gallery_resource_group, gallery_name, gallery_image_name, token)
    gallery_image_version_name = increment_version(latest_version)
    
    #create image
    create_image_definition_version(subscription_id, vm_resource_group, vm_name, location, gallery_image_name, gallery_name, gallery_image_version_name, gallery_resource_group, token)
    
