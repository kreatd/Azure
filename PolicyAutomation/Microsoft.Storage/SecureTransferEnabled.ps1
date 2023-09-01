#Requires -Modules Az.Resources, PolicyRemediation

# Configuration Changes:
# TODO: App configuration is using endkc2sbx storage account for the policy rememdiation, needs changed once new storage account location determined
# TODO: Function app outbound IPs are added to SQL database, VNET integrate app service plan, whitelist subnet

# Testing:
# TODO: Run compliance scan and make sure this works for real during an actual event firing
# TODO: Can we do a CICD process for this function app code?
# TODO: Send an e-mail (how do we want to do this, ACS or SendGrind?). Email tech contact to let know remediation ran against resource.

param (
    [Parameter(Mandatory = $true)][object]$eventGridEvent,
    [Parameter(Mandatory = $true)][object]$triggerMetadata
)

$global:ErrorActionPreference = 1 # 1 means 'Stop', 'Stop is not being recognized for some reason.

#constants:
$remediationDeploymentName = 'SecureTransferEnabled'

# mandatory configurations:
$supportsHttpsTrafficOnly = $true

# global variable for logging:
$paramsDatabaseRecord = @{
    sqlServer                = $env:sqlServer
    sqlDatabase              = $env:sqlDatabase
    eventGridEvent           = $eventGridEvent
    remediationTaskSucceeded = $false
    functionName             = $triggerMetadata.FunctionName
    exception                = $null
}

if ($eventGridEvent) {

    $resourceId = $eventGridEvent.subject

    # Get the resource whose configuration needs updated/changed
    try {
        $paramsGetStorageAccount = @{
            ResourceId = $resourceId
            ExpandProperties = $true
        }
        $storageAccount = Get-AzResource @paramsGetStorageAccount
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Change the configuration locally and update the resource in Azure
    try {
        $storageAccount.Properties.supportsHttpsTrafficOnly = $supportsHttpsTrafficOnly
        $storageAccount | Set-AzResource -Force
    }
    catch {
        $paramsDatabaseRecord.exeception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Trigger a deployment in the resource group where the offending resource exists
    # This log record provides visibility to our team as well as application owners that a remediation task ran against resources in their resource group
    try {
        $paramsDeploymentHistoryRecord = @{
            deploymentName = $env:armTemplateBaseName + '-' + $remediationDeploymentName + '-' + (Get-Date -UFormat %s)
            templateUri    = $env:armTemplateBaseUri + $env:armTemplatePolicyRemediation
            eventGridEvent = $eventGridEvent
        }

        Write-ToDeploymentHistory @paramsDeploymentHistoryRecord
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Log the remediation in our team's database for internal team visibility
    try {
        $paramsDatabaseRecord.remediationTaskSucceeded = $true
        Write-ToDatabase @paramsDatabaseRecord
    }
    catch {
        # Unable to write log to database, throw an error in the Azure function, maybe setup an alert to query the function apps runtime states?
        throw $_.Exception.Message
    }
}
else {
    throw 'Event grid data received by the Azure function is null. Remediation task cannot continue, terminating process.'
}