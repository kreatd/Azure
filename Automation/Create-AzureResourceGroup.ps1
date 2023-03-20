# #############################################################################
# 
# COMMENT:  This script creates a resource group in Azure. It is used as a
# part of the VRA workflow - "Create Azure Resource Group"
#
#
# #############################################################################

param(

    [Parameter (Mandatory = $true)]
    [string]$subscriptionName = $Null,    

    [Parameter (Mandatory = $true)]
    [ValidateSet('dev', 'tst', 'stg', 'prd', 'dr', 'trn')]
    [string]$envPrefix,

    [Parameter (Mandatory = $true)]
    [validateSet('centralus', 'eastus', 'eastus2', 'westus', 'westeurope')]
    [string]$Location,

    [Parameter (Mandatory = $true)]
    [string]$ServOwnerCC,

    [Parameter (Mandatory = $true)]
    [string]$ConsumerCC,

    [Parameter (Mandatory = $true)]
    [string]$TeamName,

    [Parameter (Mandatory = $true)]
    [string]$TechnicalContact,

    [Parameter (Mandatory = $true)]
    [ValidateSet('BG', 'BuC', 'PMC', 'PMHC')]
    [string]$DataClassification,

    #Default Value for when there is no associated Application is "NOAP"
    [Parameter (Mandatory = $False)]
    [string]$appId = "NOAP",

    #VRA Params
    $passwd,
    $username,
    $key

)

#Testing Parameters
<# -subscriptionName "" -envPrefix "DEV" -location "eastus" `
-ServOwnerCC "" -ConsumerCC "" `
-TeamName "" -TechnicalContact "" -appId "" #>

try {

    #Import Modules
    Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities
    Import-Module $PSScriptRoot\..\..\Modules\AzureResources

    #Test Import Modules (hardcoded)
    <# Import-Module "Modules\BasicUtilities.psm1"
    Import-Module "Modules\AzureResources.psm1"#>

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
    $logMessage.message = "Create-AzResourceGroup.ps1 script started"
    Write-Splunk -message $logMessage
	
    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred

    #Set the Azure Subscription Context for whatever Subscription the user selected
    Select-AzSubscription -Subscription $subscriptionName

    #Get Location Prefix based on Location (EX: Location = eastus, What gets returned is locPrefix = EA)
    $locPrefix = Get-LocationFormats -Location $Location
    $locPrefix = $LocPrefix.Location_Prefix.ToString()

    #If $locPrefix is Null exit script - May need to change to throw error
    If (!$locPrefix) {

        #Write to Splunk (Script Exiting)
        $logMessage.message = "locPrefix variable is null and did not pull back a value. Exiting script"
        Write-Splunk -message $logMessage
        exit
        
    }

    $subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

    #remove spaces,hyphens,underscores from appID   
    $appID = $appID -Replace ' ', '' -Replace '-' , '' -Replace '_' , ''

    #Trim appID so that it fits within 24 character limit for storage account names and other resources
    if ($appId.Length -gt 10) {
        $appId = ($appId.SubString(0, 9))
    }

    #Check to see if Resource Group exists
    $checkrgName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-RG-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $rgName = (Get-AzResourceGroup -ResourceGroupName $checkrgName -ErrorAction SilentlyContinue).ResourceGroupName

    #Check to see if other resources are missing
    $saName = $subPrefix.ToLower() + $locPrefix.ToLower() + "sa" + $appId.ToLower() + $envPrefix.ToLower() + "001"
    $rsvName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-RSV-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $kvName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-MKV-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $desName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-DES-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()

    #Populate names of resources if they exist
    $checksaName = (Get-AzStorageAccount -ResourceGroupName $checkrgName -Name $saName -ErrorAction SilentlyContinue).StorageAccountName
    $checkrsvName = (Get-AzRecoveryServicesVault -ResourceGroupName $checkrgName -Name $rsvName -ErrorAction SilentlyContinue).Name
    $checkkvName = (Get-AzKeyVault -ResourceGroupName $checkrgName -VaultName $kvName"*" -ErrorAction SilentlyContinue).VaultName
    $checkdesName = (Get-AzDiskEncryptionSet -ResourceGroupName $checkrgName -Name $desName -ErrorAction SilentlyContinue).Name

    #If resource group exists and resources inside exist, exit script
    if ($rgName -and $checksaName -and $checkrsvName -and $checkkvName -and $checkdesName) {

        #Write to Host
        Write-Host "Resource Group" $rgName "already exists with proper resources. Exiting script."

        #Write to Splunk (Script Exiting)
        $logMessage.message = "Resource Group" + $rgName + "already exists with proper resources. Exiting script."
        Write-Splunk -message $logMessage

        return $rgName

    }

    #If it does not exist, create the resource group via PS module
    else {

        #Create Application Based Resource Group
        CreateAppRG -subPrefix $subPrefix -envPrefix $envPrefix -Location $Location -locPrefix $locPrefix -ServOwnerCC $ServOwnerCC `
            -ConsumerCC $ConsumerCC -TeamName $TeamName -TechnicalContact $TechnicalContact -DataClassification $DataClassification `
            -deployDES $true -appId $appId

        #Write to Splunk (Script Finished)
        $logMessage.message = "Create-AzResourceGroup.ps1 script completed"
        Write-Splunk -message $logMessage

        return $rgName

    }
}

catch {

    $errorMessage = "An error has occured during the Create-AzResourceGroup.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
	
}