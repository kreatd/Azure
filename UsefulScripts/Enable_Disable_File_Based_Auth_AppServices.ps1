############################### enable/disable file authenication on app services.
# Define variables
$resourceGroupName = "RGName"
$webAppName = "WebAppName"
$configFilePath = "auth.json"
#uncomment below if you need to deploy to a slot
#$slotName="preprod"
$subscriptionId = "subscriptionid"

# Get the access token for authentication

$token = (Get-AzAccessToken).Token

# Define the REST API endpoint
#use the first url if you need to deploy to a slot
#$apiUrl = "https://management.usgovcloudapi.net/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Web/sites/$webAppName/slots/$slotName/config/authsettingsV2?api-version=2021-02-01"
$apiUrl = "https://management.usgovcloudapi.net/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Web/sites/$webAppName/config/authsettingsV2?api-version=2021-02-01"

# Define the body for the PATCH request
#if you need to disable file auth, set neabled to false and remove the configfilepath from the body.
$body = @{
    properties = @{
        platform = @{
        "enabled" = $true
        "configFilePath" = $configFilePath
        }
    }
}

# Convert the body to JSON format
$bodyJson = $body | ConvertTo-Json -Depth 10
$token = $token | convertfrom-securestring -asplaintext

# Make the REST API call to update the authentication settings
Invoke-RestMethod -Uri $apiUrl -Method PUT -Body $bodyJson -ContentType "application/json" -Headers @{
    Authorization = "Bearer $token"
}
