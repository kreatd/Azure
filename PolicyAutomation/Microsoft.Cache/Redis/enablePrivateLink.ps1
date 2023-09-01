#Requires -Modules Az.Resources, PolicyRemediation

param (
    [Parameter(Mandatory = $true)][object]$eventGridEvent,
    [Parameter(Mandatory = $true)][object]$triggerMetadata
)

#constants:
$remediationDeploymentName = 'ConfigurePrivateLinkAndVNet'

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
        $paramsGetRedisCache = @{
            ResourceId = $resourceId
            ExpandProperties = $true
        }
        $redis = Get-AzResource @paramsGetRedisCache
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    #Get the vnet and subnet info 
    try {
        if($null -eq $redis.Properties.subnetId){
            try {
                $vnet = @{
                    Name = 'vnet-'+$redis.Name
                    ResourceGroupName = $redis.resourcegroupname
                    Location = $redis.Location
                    AddressPrefix = '10.0.0.0/16'
                }
                $virtualNetwork = New-AzVirtualNetwork @vnet

                $subnet = @{
                    Name = 'subnet-'+$redis.Name
                    VirtualNetwork = $virtualNetwork
                    AddressPrefix = '10.0.0.0/24'
                }
                $subnetConfig = Add-AzVirtualNetworkSubnetConfig @subnet

                $virtualNetwork | Set-AzVirtualNetwork
            }
            catch {
                $paramsDatabaseRecord.exception = $_
                Write-ToDatabase @paramsDatabaseRecord
                throw $_.Exception.Message
            }     
            
            $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName  $redis.ResourceGroupName -Name $virtualNetwork.Name  
			 
            $subnet = $virtualNetwork | Select-Object -ExpandProperty subnets | Where-Object  {$_.Name -eq $subnet.Name}  
        }
        else {
            $redis.Properties.subnetId

            $subnetName = $redis.Properties.subnetId.split('/')[-1]
            $vNetName = $redis.Properties.subnetId.split('/')[8]
            $resourceGroup = $redis.Properties.subnetId.split('/')[4]

            $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $resourceGroup -Name $vNetName

			$subnet = $virtualNetwork | Select-Object -ExpandProperty subnets | Where-Object  {$_.Name -eq $SubnetName}  
        }
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Set up the private end point 
    try {
        $privateEndpointName = $redis.Name + "-PrivateEndPoint" 
        $privateLinkConnectionName = $redis.Name + "-ConnectionPS"

        $privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name $privateLinkConnectionName -PrivateLinkServiceId $redis.ResourceId -GroupId "redisCache"

        $privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $redis.ResourceGroupName -Name $privateEndpointName -Location $redis.Location -Subnet  $subnet -PrivateLinkServiceConnection $privateEndpointConnection
    }
    catch {
        $paramsDatabaseRecord.exception = $_
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
