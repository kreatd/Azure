# #############################################################################
#
# COMMENT:  This script creates an application gateway with the WAF v2 sku in Azure.
#
# FUTURE ENHANCEMENTS
# Add:
#   Internal & External Networking 
#   Certs
#   Listeners
#   HTTP Settings
#   Rules
#   Health Probes
#
# #############################################################################
param(

    [Parameter (Mandatory = $true)]
    [validateSet('sub1', 'sub2')]
    [string]$subscriptionName = $Null,    

    [Parameter (Mandatory = $true)]
    [ValidateSet('dev', 'tst', 'stg', 'prd', 'dr', 'trn')]
    [string]$envPrefix,

    [Parameter (Mandatory = $true)]
    [ValidateSet('centralus', 'eastus', 'eastus2', 'westus', 'northcentralus', 'southcentralus', 'westeurope', 'westcentralus', 'westus2')]
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
    [ValidateSet('BG', 'BC', 'PMC', 'PMHC')]
    [string]$DataClassification,

    #Default Value for when there is no associated Application is "NOAP"
    [Parameter (Mandatory = $true)]
    [string]$appId,

    <#
    #Can Possbly Select VNET/Subnet and Pass parameter through
    [Parameter(Mandatory=$true)]
    [ValidateSet('vnet1','vnet2')]
    [string]$vnetName,

    [Parameter(Mandatory=$true)]
    [ValidateSet('subnet1','subnet2')]
    [string]$subnetName,
    #>

    #VRA Params
    $passwd,
    $username,
    $key

)
try {
    #Import BasicUtilities module for "Location" and "Subscription" prefix cmdlet
    #Import Modules
    Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities -DisableNameChecking
    Import-Module $PSScriptRoot\..\..\Modules\AzureResources -DisableNameChecking
    Import-Module $PSScriptRoot\..\..\Modules\AzureAppgatewayWafV2 -DisableNameChecking

    
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
    $logMessage.message = "Create-AzureAppGatewayWafV2.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    $azSession = Login-AzAccount -Credential $cred


    #Trim appID so that it fits within 24 character limit for storage account names and other resources
    if ($appId.Length -gt 9) {

        $appId = ($appId.SubString(0, 9))

    }

    #Format AppID  
    $appId = $appId -Replace ' ', '' -Replace '-' , '' -Replace '_' , ''
    $appId = $appId.ToUpper()

    #Get Location Prefix based on Location (EX: Location = eastus, What gets returned is locPrefix = EA)
    $locPrefix = (Get-LocationFormats -Location $Location).Location_Prefix.ToString()

    #If $locPrefix is Null exit script - May need to change to throw error
    If (!$locPrefix) {

        #Write to Splunk (Script Exiting)
        $logMessage.message = "locPrefix variable is null and did not pull back a value. Exiting script"
        Write-Splunk -message $logMessage
        throw $logMessage.message
    
    }

    $subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

    #Set the Azure Subscription Context for whatever Subscription the user selected
    $azsubscription = Select-AzSubscription -Subscription $subscriptionName

    #set variables
    $rgName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-RG-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $appGwName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-AGW-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()

    #check resources
    $checkrgName = (Get-AzResourceGroup -ResourceGroupName $rgName -ErrorAction SilentlyContinue).ResourceGroupName
    $checkappGwName = (Get-AzApplicationGateway -Name $appGwName -ErrorAction SilentlyContinue).Name

    #If resource group exists and resources inside exist, exit script
    if ($checkrgName) {
       #Write to Splunk
        $logMessage.message = "Resource Group [$rgName] already exists."
        Write-Splunk -message $logMessage
        
    }

    #If it does not exist, create the resource group via PS module
    else {

        #Write to Splunk
        $logMessage.message = "Resource Group " + $rgName + " was not found, resource group has been created in $subscriptionName."
        Write-Splunk -message $logMessage

        #Create Application Based Resource Group
        $azAppRG = CreateAppRG -subPrefix $subPrefix -envPrefix $envPrefix -Location $Location -locPrefix $locPrefix -ServOwnerCC $ServOwnerCC `
            -ConsumerCC $ConsumerCC -TeamName $TeamName -TechnicalContact $TechnicalContact -DataClassification $DataClassification `
            -deployDES $false -appId $appId

    }
    
    #Check if Application gateway exist
    If ($checkappGwName) {
    
        #Write to Host
        $azAppGw ="Application Gateway $appGwName already exists. Exiting Script"

        #Write to Splunk (Script Exiting)
        $logMessage.message = "Application Gateway " + $appGwName + " already exists. Exiting Script."
        Write-Splunk -message $logMessage
             
    }
    Else {
        #Write to Splunk
        $logMessage.message = "Application Gateway " + $appGwName + " was not found, creating app gateway in $rgName ..."
        Write-Splunk -message $logMessage

        #Create the Default Application Gateway
        $appGw = CreateAzApplicationGatewayWafv2 -rgName $rgName -appGwName $appGwName -subscriptionName $subscriptionName #-vnetName $vnetName -subnetName $subnetName -default $true

        #Write to Splunk
        $logMessage.message = "Application Gateway " + $appGwName + " created Successfully in $rgName!"
        Write-Splunk -message $logMessage

        $azAppGw ="Application Gateway $appGwName created Successfully in $rgName!"
       
    }
}
catch {
    $errorMessage = "An error has occured during the Create-AzureAppGatewayWafV2.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
}

return $azAppGw
