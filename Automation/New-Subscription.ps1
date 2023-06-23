
$subName = "enter name of sub"
$subPrefix = "enter sub prefix"
$location = "eastus"
$Environment = "PRD"

$templateFilePath = "\\Create-SHSAAlert.json"
$DataClassification = "enter info"
$appId = "enter info"

if ($location -eq "eastus") {
    $locPrefix = "EA"
} elseif ($location -eq "eastus2") {
    $locPrefix = "EA2"
} elseif ($location -eq "centralus") {
    $locPrefix = "CU"
} elseif ($location -eq "westeurope") {
    $locPrefix = "WE"
} else {
    Write-Output "Location is missing..."
}


$resourceGroup = "$subPrefix-$locPrefix-RG-$appId-$Environment"
$systemTopicName = "$subPrefix-$locPrefix-EGST-$appId-$Environment"
$eventGridSubscriptionName = "$subPrefix-$locPrefix-EGS-$appId-$Environment"



Import-Module $PSScriptRoot\..\..\..\..\..\Modules\MSGraphUtils



function find-subid {
    param (
        $SubName
    )
    $ErrorActionPreference = 'Stop'
    try {
        $subId = (Get-AzSubscription -SubscriptionName $SubName | Select-Object Id).Id
    }
    catch {
        ## need to end script here if fails to find subscription
        throw "Unable to find a subscription with the provided name."
    }
    
    return $subId
}

function add-to-ecs-dev {
    param (
        $SubName,
        $SubPrefix,
        $SubId,
        $dbToken
    )
   
    # dev db
    $dbServer = "name of dev db.database.windows.net"
    $db = "name of dev db"  

    $searchQuery = "SELECT * FROM Azure_Subscription_Prefix WHERE Subscription_Prefix = '$SubPrefix' OR Subscription_Id = '$SubId'"
    $verify = Invoke-Sqlcmd -Query $searchQuery -ServerInstance $dbServer -Database $db -AccessToken $dbToken
    if (!$verify) {
        $query = "INSERT INTO Azure_Subscription_Prefix (Subscription_Prefix, Subscription_Name, Subscription_Id) VALUES ('$SubPrefix','$SubName','$SubId')"
        Invoke-Sqlcmd -Query $query -ServerInstance $dbServer -Database $db -AccessToken $dbToken
    }
    else {
        write-output "A subscription with the same prefix and/or subscription id already exists in this database. Skipping..."
    }  
}

function add-to-ecs-prd {
    param (
        $SubName,
        $SubPrefix,
        $SubId
    )
   
    # prd db
    $dbServer = "name of prd db.database.windows.net"
    $db = "name of prd db"

    $searchQuery = "SELECT * FROM Azure_Subscription_Prefix WHERE Subscription_Prefix = '$SubPrefix' OR Subscription_Id = '$SubId'"
    $verify = Invoke-Sqlcmd -Query $searchQuery -ServerInstance $dbServer -Database $db -AccessToken $dbToken
    if (!$verify) {
        $query = "INSERT INTO Azure_Subscription_Prefix (Subscription_Prefix, Subscription_Name, Subscription_Id) VALUES ('$SubPrefix','$SubName','$SubId')"
        Invoke-Sqlcmd -Query $query -ServerInstance $dbServer -Database $db -AccessToken $dbToken
    }
    else {
        write-output "A subscription with the same prefix and/or subscription id already exists in this database. Skipping..."
    }  
}


function add-to-cncp-db {
    param (
        $SubName,
        $SubPrefix,
        $SubId
    )
    # naming convention db info
    $dbServer = "name of naming convention db.database.windows.net"
    $db = "name of naming convention db"

    $searchQuery = "SELECT * FROM Azure_Subscription_Prefixes WHERE Subscription_Prefix = '$SubPrefix' OR Subscription_Id = '$SubId'"
    $verify = Invoke-Sqlcmd -Query $searchQuery -ServerInstance $dbServer -Database $db -AccessToken $dbToken
    if (!$verify) {
        $query = "INSERT INTO Azure_Subscription_Prefixes (Subscription_Prefix, Subscription_Name, Subscription_Id) VALUES ('$SubPrefix','$SubName','$SubId')"
        Invoke-Sqlcmd -Query $query -ServerInstance $dbServer -Database $db -AccessToken $dbToken
    }
    else {
        write-output "A subscription with the same prefix and/or subscription id already exists in this database. Skipping..."
    }  
}

function register-providers {
    param(
        $subName
    )
    #Set-AzContext $SubName
    # list of basic resource providers, may not be all inclusive
    $providers = @(
        'Microsoft.ADHybridHealthService', 
        'Microsoft.Advisor',
        'Microsoft.AlertsManagement', 
        'Microsoft.Authorization',
        'Microsoft.Billing',
        'Microsoft.ClassicSubscription',
        'Microsoft.CloudShell',
        'Microsoft.Commerce',
        'Microsoft.Compute',
        'Microsoft.Consumption',
        'Microsoft.CostManagement',
        'Microsoft.Diagnostics',
        'Microsoft.EventGrid',
        'Microsoft.EventHub',
        'Microsoft.Features',
        'Microsoft.GuestConfiguration',
        'microsoft.insights',
        'Microsoft.KeyVault',
        'Microsoft.Logic',
        'Microsoft.ManagedIdentity',
        'Microsoft.MarketplaceNotifications',
        'Microsoft.MarketplaceOrdering',
        'Microsoft.Network',
        'Microsoft.OperationalInsights',
        'Microsoft.OperationsManagement',
        'Microsoft.PolicyInsights',
        'Microsoft.Portal',
        'Microsoft.RecoveryServices',
        'Microsoft.ResourceGraph',
        'Microsoft.ResourceHealth',
        'Microsoft.Resources',
        'Microsoft.Security',
        'Microsoft.SerialConsole',
        'Microsoft.ServiceLinker',
        'Microsoft.SqlVirtualMachine',
        'Microsoft.Storage',
        'microsoft.support',
        'Microsoft.Web'
    )
    foreach ($provider in $providers) {
        Register-AzResourceProvider -ProviderNamespace $provider
    } 
}

function set-diagnosticsettings {
    param(
        $subName,
        $subID,
        $location
    )

    $sub = get-azsubscription | where {$_.name -like $subName}

    $logSettingObj = New-AzDiagnosticSettingLogSettingsObject -Enabled $true -CategoryGroup allLogs `
    -RetentionPolicyDay 0 -RetentionPolicyEnabled $false

    New-AzDiagnosticSetting -resourceid "/subscriptions/$sub" -log $logSettingObj `
    -Name "$subName Activity to event hub" -EventHubName "name of event hub" `
    -EventHubAuthorizationRuleId "enter splunkaccesspolicyid"
   

}

function deploy-securityAdvisoryHealthAlert {
    param(
        $subName,
        $subID,
        $templateFilePath,
        $envrionment
    )

    $rgName = get-azresourcegroup | where {$_.resourcegroupname -like $appId} | select -first 1
    $activityLogAlertName = $rgName.resourcegroupname.replace("RG","SHSAA")
  
    New-AzResourceGroupDeployment -ResourceGroupName $rgName.ResourceGroupName `
    -TemplateFile $templateFilePath `
    -activityLogAlerts $activityLogAlertName `
    -ActionGroup "action group id" `
    -Scope "/subscriptions/$subID" `
    -Environment $environment
}

function Add-azRGPolicy(){

    param(
    [parameter (Mandatory=$true)]
    $ConsumerCC,
    [parameter (Mandatory=$true)]
    $ServOwnerCC,
    [parameter (Mandatory=$true)]
    $TeamName,
    [parameter (Mandatory=$true)]
    $TechnicalContact,
    [parameter (Mandatory=$true)]
    $DataClassification,
    [parameter (Mandatory=$true)]
    $appId,
    [parameter (Mandatory=$true)]
    $resourceGroup,
    [parameter (Mandatory=$false)]
    $environment
    )

    $rg = Get-AzResourceGroup -Name $resourceGroup
    if($rg.name -like "*networking rg name*"){
        $envPrefix = $environment
    }else{
    $envPrefix = $rg.name -replace '^.*(?=.{3}$)'
    }
    $RGID = $rg.ResourceId
    
    #Assign Initiative Definition - Resource Group Tags
    $Definition = Get-AzPolicySetDefinition -Id "id of our resource group tagging policy definition"
        
    #Assign Tagging Policy
    $appId = $appId.ToUpper()
    New-AzPolicyAssignment -Name "RG - Tags - $resourceGroup" -Scope "$RGId" `
        -ConsumerCostCenter "$ConsumerCC" -TeamName "$TeamName" -TechnicalContact "$TechnicalContact" `
        -AppTag $appId -Environment $envPrefix -ServiceOwnerCostCenter "$ServOwnerCC" `
        -DataClassification $DataClassification -PolicySetDefinition $Definition

}
function Deploy-azEventGridSystemTopic() {
  param (
  
    [parameter (Mandatory=$true)]
    [object] $subscription,
    [parameter (Mandatory=$true)]
    [object] $resourceGroup,
    [parameter (Mandatory=$true)]
    [object] $systemTopicName,
    [parameter (Mandatory=$true)]
    [object] $eventGridSubscriptionName,
    [parameter (Mandatory=$true)]
    [object] $ConsumerCC,
    [parameter (Mandatory=$true)]
    [object] $ServOwnerCC,
    [parameter (Mandatory=$true)]
    [object] $TeamName,
    [parameter (Mandatory=$true)]
    [object] $TechnicalContact,
    [parameter (Mandatory=$true)]
    [object] $DataClassification,
    [parameter (Mandatory=$true)]
    [object] $appId,
    [parameter (Mandatory=$true)]
    [object] $location

  )

$subscription = get-azSubscription -SubscriptionName $subscription
#Set-azcontext -Subscription $subscription.SubscriptionId
$rg = Get-AzResourceGroup -name $resourceGroup

try{

#If resource group does not exist, create new resource group and apply our tagging policy
if(!$rg){
New-AzResourceGroup -Name $resourceGroup -Location $location
Add-azRGPolicy -ConsumerCC $ConsumerCC -ServOwnerCC $ServOwnerCC -TeamName $TeamName `
-TechnicalContact $TechnicalContact -DataClassification $DataClassification -appId $appId -resourceGroup $resourceGroup
}

#create event grid system topic
$newSystemTopic = New-AzEventGridSystemTopic -resourcegroupname $resourceGroup `
 -name $systemTopicName `
 -source "/subscriptions/$($subscription.SubscriptionId)" `
 -topictype "Microsoft.Resources.Subscriptions" `
 -Location global

#create and apply a lock to the event grid system topic
 New-AzResourceLock -LockLevel CanNotDelete `
 -LockNotes "Please contact enter email here if you'd like to delete" `
 -LockName "CreatedByCreatedDateTagging" `
 -ResourceName $newSystemTopic.topicname `
 -ResourceType "Microsoft.EventGrid/systemTopics" `
 -ResourceGroupName $resourceGroup `
 -Force

#create event gid subscription and apply the necessary filters
 $AdvFilter1=@{operator="StringNotIn"; key="data.operationName"; Values=@("Microsoft.Resources/tags/write","Microsoft.Resources/deployments")}
 $AdvancedFilters=@($AdvFilter1)
 $includedEventTypes = "Microsoft.Resources.ResourceWriteSuccess"
 New-AzEventGridsystemtopiceventSubscription -systemTopicName $newSystemTopic.TopicName `
 -ResourceGroupName $newSystemTopic.resourcegroupname `
 -EventSubscriptionName $eventGridSubscriptionName `
 -EndpointType "azurefunction" `
 -AdvancedFilter $AdvancedFilters `
 -IncludedEventType $includedEventTypes `
 -Endpoint "the function app that performs the created by date / name tags" 
}catch{
    write-output "Error during system topic creation...."
    $_
}
}

## code execution ##
$SubID = find-subid -SubName $SubName

Set-azContext -Subscription $subName
# generate token using function from GraphUtils
$dbToken = GetDBAccessToken

Write-Output "Registering resource providers. Note that there may be additional resource providers to register given the specific needs of the subscription."
register-providers -SubName $SubName

Write-Output "Deploying the event grid system topic for created by / created date taging"
Deploy-azEventGridSystemTopic -subscription $subName -resourcegroup $resourceGroup -systemTopicName $systemTopicName `
-eventGridSubscriptionName $eventGridSubscriptionName -ConsumerCC "static info" -ServOwnerCC "static info" `
-TeamName "static info" -TechnicalContact "static info" -DataClassification "Business General" -appId "static info" `
-location $location

Write-Output "Deploying the security advisory health alert"
deploy-securityAdvisoryHealthAlert -SubName $SubName -SubId $SubID -templateFilePath $templateFilePath -envrionment $Environment

Write-Output "Configure the diagnostic Settings"
set-diagnosticsettings -SubName $SubName -SubId $SubID -location $location

Write-Output "Adding to dev database"
add-to-ecs-dev -SubName $SubName -SubPrefix $SubPrefix -SubId $SubID -dbToken $dbToken

Write-Output "Adding to prd database"
add-to-ecs-prd -SubName $SubName -SubPrefix $SubPrefix -SubId $SubID -dbToken $dbToken

Write-Output "Adding to naming convention prd database"
add-to-cncp-db -SubName $SubName -SubPrefix $SubPrefix -SubId $SubID -dbToken $dbToken
Write-Output "Creating team Resource Group and Event Grid System Topic"


Write-Output "Creating the networking resource group for Datacom"
New-AzResourceGroup -name "$subprefix-$locPrefix-naming convention for networking rg" -location $location

Write-Output "Applying the RG Policy to the naming convention for networking rg resource group"
Add-azRGPolicy -ConsumerCC "static info" -ServOwnerCC "static info" -TeamName "static info" `
-TechnicalContact "static info" -DataClassification $DataClassification -Environment $environment -appId $appId -resourceGroup "$subprefix-$locPrefix-naming convention for networking rg"

Write-Output "Enabling Microsoft Defender for Cloud defender plans"
$defenderPlans = get-azsecuritypricing

foreach($plan in $defenderPlans){
    Set-AzSecurityPricing -name $plan.name -PricingTier Standard
}

Write-Output "Complete"
