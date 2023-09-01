#Requires -Modules Az.Resources, PolicyRemediation

param (
    [Parameter(Mandatory = $true)][object]$eventGridEvent,
    [Parameter(Mandatory = $true)][object]$triggerMetadata
)

#constants:
$remediationDeploymentName = 'EnableSecureConnection'

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
    $subscriptionId = $eventGridEvent.data.subscriptionId

    $paramsSetAzContext = @{ SubscriptionId = $subscriptionId }
    Set-AzContext @paramsSetAzContext

    try {
        $paramsGetResource = @{
            ResourceId = $resourceId
            ExpandProperties = $true
        }
        $resource = Get-AzResource @paramsGetResource
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    try {
        $serverParameterName  = 'require_secure_transport'
        $serverParameterValue = 'ON' 
        $paramsEnforceSslConnections = @{
            ResourceGroupName = $resource.ResourceGroupName
            ServerName        = $resource.name
            Name              = $serverParameterName
            Value             = $serverParameterValue

        }
 
        Update-AzPostgreSqlFlexibleServerConfiguration @paramsEnforceSslConnections
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