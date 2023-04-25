##Update techincal contact field on all resources within a resource group 

$mergedTags = @{"key"="value";} 
$resources = get-azresource –resourcegroupname "" 

foreach($resource in $resources) 
{ 
  Update-AzTag -ResourceId $resource.resourceid -Tag $mergedTags -Operation Replace 
} 

 

 
##### report on keyvaults for security 

$subs = get-azsubscription 
 
foreach($sub in $subs){ 

    set-azcontext $sub 
    $keyVaults = get-azkeyvault 
    $keyVaultCerts =@() 


foreach($vaultName in $keyVaults){ 

    $keyVaultCerts += get-azkeyvaultcertificate -VaultName $vaultname.vaultname 

    } 

    Write-output "There are $($keyVaults.count) Azure Key Vaults in $($sub.name)" 
    Write-output "There are $($keyVaultCerts.count) Certificates in $($sub.name)" 

}  
##### 

#Set get/list access to kvs 

$objectid = "" 

$subs = Get-AzSubscription 

foreach($sub in $subs){ 

    set-azcontext $sub 

    $keyVaults = get-azkeyvault 

   

foreach($vaultName in $keyVaults){ 

    Set-AzKeyVaultAccessPolicy -VaultName $vaultName.vaultname -ObjectId $objectID -PermissionsToCertificates Get,List -whatif 

    } 

} 

#### 

#Set diagnostic setting on an application gateway 

Function newAppGwDiagSetting { 

    Param ( 

    [Parameter(Mandatory = $True)] 

    [string]$appGwName 

) 

$appgw = Get-AzApplicationGateway -name $appGwName 

$logSettingObj = New-AzDiagnosticSettingLogSettingsObject -Enabled $true -CategoryGroup allLogs -RetentionPolicyDay 0 -RetentionPolicyEnabled $false 

$MetricSettingObj = New-AzDiagnosticSettingMetricSettingsObject -Enabled $false -Category AllMetrics -RetentionPolicyDay 0 -RetentionPolicyEnabled $false 

New-AzDiagnosticSetting -resourceid $appgw.id -log $logSettingObj -Metric $MetricSettingObj -Name "AGWActivity to xxxxx" -EventHubName "xxxx" -EventHubAuthorizationRuleId "xxxxx" 

} 

 

#### 

#Pull all policy assignments 

Get-AzPolicyAssignment | Select-Object -ExpandProperty properties | Select-Object -Property Scope, PolicyDefinitionID, DisplayName 

 

#### 

#Get resource types from a resource provider 

$x=Get-AzResourceProvider -ListAvailable  | where {$_.ProviderNamespace -eq "Dynatrace.Observability"} | select ResourceTypes 

$x.resourcetypes.resourcetypename 

#### 

#Get the consumptionusage of a resource 

$costs = Get-AzConsumptionUsageDetail -StartDate (Get-Date).AddDays(-1) -EndDate (Get-Date) -InstanceName "vmname" 

$sum = $costs | measure -Property 'PretaxCost' -sum 

$USDCost = '{0:C}' -f $sum.Sum 

#### 

#Convert keyvault from standard to premium 

$vault = get-azresource -ResourceName resourcename -resourcegroupname resourcegroupname –ExpandProperties 

$vault.Properties.sku.name = 'Premium' 

Set-AzResource -ResourceId $vault.ResourceId -Tags $vault.Tags -Properties $vault.Properties -force -whatif 

#(confirm change with) 

get-azkeyvault -name resourcename | select sku 

#### 

#Enable SQL Server Auditing on all SQL servers within the current subscription context (get-azcontext) 

Get-AzSqlServer | Set-AzSqlServerAudit -EventHubTargetState Enabled -EventHubName 'xxxxx' -EventHubAuthorizationRuleResourceId 'xxxxxx' -whatif 

 

### 

#Tag VMs 

$tag=@{ "VMBackup" = "FALSE"} 

$test = get-azvm | where {$_.name -eq "vmname"} 

Set-AzResource -ResourceGroupName $test.ResourceGroupName -Name $test.name -ResourceType "Microsoft.Compute/VirtualMachines" -Tag $tag –force -whatif 

### 

#Get az vm disk encryption status 

$subs = get-azsubscription 

$a=@() 

foreach($sub in $subs){set-azcontext $sub;$vms=get-azvm | select name,resourcegroupname;foreach($vm in $vms){$a+=Get-AzVmDiskEncryptionStatus -ResourceGroupName $vm.resourcegroupname -VMName $vm.name | select *,@{n="name,rg";e={$vm.name,$vm.resourcegroupname}}}} 

##### 

  

Get-azStorageContainer -Container '$web' -context $context| Set-azStorageBlobContent -File "test.txt" -Blob "test" -Force -Properties @{ ContentType = "text/html; charset=utf-8"; } 

##### 

#GET; 

Get-AzStorageBlob -Container $container -Blob "*" -Context $context | foreach { $_.ICloudBlob.Properties.ContentType} 

#SET; 

Get-AzStorageBlob -Container $container -Blob "*" -Context $context | foreach { $_.ICloudBlob.Properties.ContentType = 'text/html'; $_.ICloudBlob.SetProperties() } 

##### 

  

$metricoutput=get-azresource -ResourceGroupName "xxxxx" | Get-AzMetricAlertRuleV2 

  

$alertoutput=get-azresource -ResourceGroupName "xxxxx" | Get-AzAlertRule 

  

 

$x=Get-AzVirtualNetwork 
$hash=@{} 
foreach($out in $x){$hash.add($out.name,$out.dhcpoptions.dnsservers)} 
$hash 

  

  

#Find resource aliases: 

(Get-AzPolicyAlias -NamespaceMatch 'Microsoft.Compute' -ResourceTypeMatch 'virtual' ).Aliases ` 
| Where-Object Name -match image | Select-Object Name 

  

  

get-azresource | select name,@{n="App Tag";e={$_.tags.'App Tag'}} 

  

$subs = get-azsubscription                                                                                                                                

$t=@() 

foreach($sub in $subs){set-azcontext $sub;$t+=get-azvm | select name,@{Name="Team Tag";Expression={($_.tags.'Team Name')}},subscription,id} 

  

$arrout = @() 

$x = get-azroledefinition # | select -first 10 

foreach($role in $x){ 

    $arrout += get-azroleassignment | where {$_.RoleDefinitionName -eq $role.name} 

} 

$arrout | select DisplayName, RoleDefinitionName , Scope 

 
