# #############################################################################
# 
#
# VERSION HISTORY
# 1.0 - 07/07/2022 - Created
# 1.1 - 09/13/2022 - VRA Push Enchancements
# 
# FUTURE ENHANCEMENTS
#
# #############################################################################

param(

    [Parameter (Mandatory = $true)]
    [validateSet('App', 'Team', 'SBX')]
    [string] $rgType ,

    [Parameter (Mandatory = $true)]
    [validateSet('PRD', 'DEV', 'TST', 'POC', 'STG', 'DR', 'TRN')]
    [string]$envPrefix ,    

    [Parameter (Mandatory = $true)]
    [validateSet('sub1', 'sub2')]
    [string]$subscriptionName = $Null ,

    [Parameter (Mandatory = $true)]
    [validateSet('centralus', 'eastus', 'eastus2', 'westus', 'westeurope')]
    [string] $location ,

    [Parameter (Mandatory = $true)]
    [string]$ServOwnerCC ,

    [Parameter (Mandatory = $true)]
    [string] $ConsumerCC ,

    [Parameter (Mandatory = $true)]
    [string] $TeamName ,
    
    [Parameter (Mandatory = $true)]
    [string] $TechnicalContact ,
    
    [Parameter (Mandatory = $true, HelpMessage = "sharepointsite/file.html")]
    [validateSet('BG', 'BC', 'PMC', 'PMHC')]
    [string] $DataClassification ,

    [Parameter (Mandatory = $false)]
    [string] $appId = "NOAP" ,
    
    [Parameter (Mandatory = $true, HelpMessage = "Are Virtual Machines going to be deployed? If so, the resource group will need a Disk Encryption Set.")]
    [bool] $deployDES = $false,

    #Default Value when empty is not passed is "$false" - all resources will get deployed
    [Parameter (Mandatory = $false, HelpMessage = "If enabled, this will create a blank Azure Resource Group. If this need is unknown, leave false.")]
    [bool]$empty = $false,

    #Parameters we need to hide depending on which $rgType is select
    #rgType = Team
    [Parameter(Mandatory = $false)]
    [string] $RGTeamName,
    
    #$rgType = SBX
    [Parameter (Mandatory = $false)]
    [string] $SBXName,

    #VRA Params
    $passwd,
    $username,
    $key

)

#Import Module
#Import BasicUtilities module for "Location" and "Subscription" prefix cmdlet
Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities -DisableNameChecking
Import-Module $PSScriptRoot\..\..\Modules\AzureResources -DisableNameCheck

#Splunk logging 
#Import Splunk Library
Import-Module -name "\\path\to\modules\internal\Splunk.Internal"
	
#Setting up logging object
$logMessage = @{
    params  = @{}
    details = @{}
    message = $null
}

#Setting parameters for Splunk logging
$logMessage.details["subscriptionName"] = $subscriptionName
$logMessage.details["envPrefix"] = $envPrefix
$logMessage.details["location"] = $location
$logMessage.details["ServOwnerCC"] = $ServOwnerCC
$logMessage.details["ConsumerCC"] = $ConsumerCC
$logMessage.details["TeamName"] = $TeamName
$logMessage.details["TechnicalContact"] = $TechnicalContact
$logMessage.details["DataClassification"] = $DataClassification
$logMessage.details["appId"] = $appId
$logMessage.details["username"] = $username

#Write to Splunk (Script Starting)
$logMessage.message = "CreateAzResourceGroup.ps1 script started"
Write-Splunk -message $logMessage

#Log into azure using encrypted PW from parameter
#Needs commented out when testing outside of VRA
try { 
    $logMessage.message = "Logging into Azure..."
    Write-Splunk -message $logMessage
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    $azSession = Login-AzAccount -Credential $cred

}
catch {
    $errorMessage = "An error has occured attempting to login to Azure during the CreateAzResourceGroup.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
}
#Set subscription context
try {
    $logMessage.message = "Selecting subscription: $subscriptionName..."
    Write-Splunk -message $logMessage
    Select-AzSubscription -Subscription $subscriptionName
}
catch {
    $errorMessage = "An error has occured attempting to select subscription during the CreateAzResourceGroup.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
}
#Obtain Subscription Prefix
$subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

#If $locPrefix is Null exit script - May need to change to throw error
If (!$subPrefix) {

    #Write to Splunk (Script Exiting)
    $logMessage.message = "subPrefix variable is null and did not pull back a value. Exiting script"
    Write-Splunk -message $logMessage
    exit
    
}

#Obtain Location Prefix
$locPrefix = (Get-LocationFormats -Location $Location).Location_Prefix.ToString()

#If $locPrefix is Null exit script - May need to change to throw error
If (!$locPrefix) {

    #Write to Splunk (Script Exiting)
    $logMessage.message = "locPrefix variable is null and did not pull back a value. Exiting script"
    Write-Splunk -message $logMessage
    exit
    
}

Switch ($rgType) {
    App {
        $logMessage.message = "Creating APP Resource Group..."
        Write-Splunk -message $logMessage
        CreateAppRG -subPrefix $subPrefix -envPrefix $envPrefix -location $location `
            -locPrefix $locPrefix -ServOwnerCC $ServOwnerCC -ConsumerCC $ConsumerCC `
            -TeamName $TeamName -TechnicalContact $TechnicalContact -DataClassification $DataClassification -appId $appId -deployDES:$deployDES -empty:$empty
    }
    Team {
        $logMessage.message = "Creating TEAM Resource Group..."
        Write-Splunk -message $logMessage
        CreateTeamRG -subPrefix $subPrefix -envPrefix $envPrefix -location $location -locPrefix $locPrefix `
            -RGTeamName $RGTeamName -ServOwnerCC $ServOwnerCC -ConsumerCC $ConsumerCC -TeamName $TeamName `
            -TechnicalContact $TechnicalContact -DataClassification $DataClassification -appId $appId -deployDES:$deployDES -empty:$empty
    }
    SBX {
        $logMessage.message = "Creating SBX Resource Group..."
        Write-Splunk -message $logMessage
        CreateSBXRG -subPrefix $subPrefix -SBXName $SBXName `
            -location $location -locPrefix $locPrefix -ServOwnerCC $ServOwnerCC `
            -ConsumerCC $ConsumerCC -TeamName $TeamName `
            -TechnicalContact $TechnicalContact -DataClassification $DataClassification -appId $appId -deployDES:$deployDES -empty:$empty
    }
}
<#try{}
catch {
    $errorMessage = "An error has occured attempting to create the Resource Group in the CreateAzResourceGroup.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
}
#>

