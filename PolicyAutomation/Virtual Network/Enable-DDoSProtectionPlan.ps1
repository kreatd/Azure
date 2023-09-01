Connect-AzAccount 

Set-AzContext -Subscription "ECS3"

$resource = get-azresource -name "vnet-nate-test"

$sub = Get-AzContext 

$resourceId = $resource.ResourceId
$subscriptionId = $sub.Name

#Requires -Modules Az.Resources, PolicyRemediation

param (
    [Parameter(Mandatory = $true)][object]$eventGridEvent,
    [Parameter(Mandatory = $true)][object]$triggerMetadata
)

#constants:
$remediationDeploymentName = 'EnableDDoSProtectionPlan'

# mandatory configurations:
$enableDDoSProtection = $true

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
    $subscriptionId = $eventGridEvent.topic.split('/')[2]
    try {
        $paramsSetAzContext = @{ SubscriptionId = "$subscriptionId" }
        Set-AzContext @paramsSetAzContext
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Get the resource whose configuration needs updated/changed
    try {
        $paramsGetVNetCache = @{
            ResourceId = $resourceId
            ExpandProperties = $true
        }
        $resource = Get-AzResource @paramsGetVNetCache

        $vnet = Get-AzVirtualNetwork -Name $resource.Name 
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Get the DDoS Protection Plan 
    try {
        $ddosProtectionPlan = Get-AzDdosProtectionPlan 

        if(!$ddosProtectionPlan){
            $loc = $vnet.ResourceGroupName.Split('-')[1]
            $subAbr = $vnet.ResourceGroupName.Split('-')[0]
            $env = $vnet.ResourceGroupName.Split('-')[-1]
            
            $rgName = $subAbr + "-" + $loc + "-RG-AZDDOS" + "-" + $env

            $ddosRG = Get-AzResourceGroup -Name $rgName

            if(!$ddosRG){
                $ddosRG = New-AzResourceGroup -Name $rgName -Location $vnet.Location
            }

            $ddosProtectionPlan = New-AzDdosProtectionPlan -ResourceGroupName $ddosRG.ResourceGroupName -Name $ddosRG.ResourceGroupName -Location $ddosRG.Location
        }
    }
    catch { 
        $paramsDatabaseRecord.exeception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Change the configuration locally and update the resource in Azure
    try {
        $vnet.DdosProtectionPlan = New-Object Microsoft.Azure.Commands.Network.Models.PSResourceId

        $vnet.DdosProtectionPlan.Id = $ddosProtectionPlan.Id
        $vnet.EnableDdosProtection = $enableDDoSProtection
        $vnet | Set-AzVirtualNetwork
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