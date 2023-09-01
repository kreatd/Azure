#Requires -Modules Az.Resources, Az.Sql, PolicyRemediation

param (
    [Parameter(Mandatory = $true)][object]$eventGridEvent,
    [Parameter(Mandatory = $true)][object]$triggerMetadata
)

#! Public Network Access MUST be enabled for the firewall rules to take effect!

#constants:
$remediationDeploymentName = 'AddUpmcExpressRouteIps'

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

        # UPMC Express Route IP addresses as of 08.17.2023
        # 198.99.201.0/24
        # 198.136.8.0/24
        $firewallRules = New-Object System.Collections.ArrayList
        $null = $firewallRules.add( @{ Name = 'UPMC-Express-Route-001' ; StartIpAddress = '198.99.201.0' ; EndIpAddress = '198.99.201.255'} )
        $null = $firewallRules.add( @{ Name = 'UPMC-Express-Route-002' ; StartIpAddress = '198.136.8.0'  ; EndIpAddress = '198.136.8.255'} )
        
        foreach ($firewallRule in $firewallRules) {
            $paramsNewFirewallRule = @{
                ResourceGroupName = $resource.ResourceGroupName
                ServerName        = $resource.Name
                FirewallRuleName  = $firewallRule.Name
                StartIpAddress    = $firewallRule.StartIpAddress
                EndIpAddress      = $firewallRule.EndIpAddress
            }
            New-AzSqlServerFirewallRule @paramsNewFirewallRule
        }
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