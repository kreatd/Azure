# #############################################################################
# 
# COMMENT:  This script creates and deploys an Azure Virtual Machine using the
# parameters defined below. This script is leveraged as part of the VRA flow:
# "Azure - Create Windows Virtual Machine"
#
# #############################################################################

#Parameters
Param(

    #Azure Subscription
    [Parameter (Mandatory = $True)]
    [string]$subscriptionName,   

    #Virtual Machine / Server Name
    [Parameter (Mandatory = $True)]
    [string]$vmName,

    #Operating System / Image for Server
    [Parameter (Mandatory = $True)]
    [string]$OS,

    #If VM will be always on or if it will power on/off via schedule
    [Parameter (Mandatory = $True)]
    [string]$alwaysOn,

    #Time for VM to Power On (if $alwaysOn = false)
    [Parameter (Mandatory = $False)]
    [int]$powerOnTime,

    #Time for VM to Power Off (if $alwaysOn = false)
    [Parameter (Mandatory = $False)]
    [int]$powerOffTime,

    #Resource Group to be leveraged
    [Parameter (Mandatory = $True)]
    [string]$rg,

    #Virtual Network to be leveraged
    [Parameter (Mandatory = $True)]
    [string]$virtualNetworkName,

    #Subnet to be leveraged
    [Parameter (Mandatory = $True)]
    [string]$subnetName,

    #Azure template size of the server
    [Parameter (Mandatory = $True)]
    [string]$vmSize,

    #Azure Geographic Location
    [Parameter (Mandatory = $True)]
    [string]$Location,

    #Domain Name (for Domain Join)
    [Parameter (Mandatory = $True)]
    [string]$domainName,

    #Domain Username (for Domain Join)
    [Parameter (Mandatory = $True)]
    [string]$domainUsername,

    #OU Path (for Domain Join / AD)
    [Parameter (Mandatory = $True)]
    [string]$ouPath,

    #Application ID from/for Cherwell
    #Default Value for when there is no associated Application is "NOAP"
    [Parameter (Mandatory = $False)]
    [string]$appId = "NOAP",

    #Environment Prefix
    [Parameter (Mandatory = $True)]
    [string]$EnvPrefix,

    #Time Zone
    [Parameter (Mandatory = $True)]
    [ValidateSet('Eastern Standard Time', 'SE Asia Standard Time', 'Central Standard Time', 'Pacific Standard Time', 'Central European Standard Time', 'GMT Standard Time', 'Tokyo Standard Time', 'E. South America Standard Time', 'E. Australia Standard Time', 'India Standard Time', 'Canada Central Standard Time', 'Mountain Standard Time', 'Korea Standard Time', 'Aus Central W. Standard Time')]
    [string]$timeZone,

    #AvailabilitySetName Prefix
    [Parameter (Mandatory = $False)]
    [string]$availabilitySetName,

    #OS Support Team
    [Parameter (Mandatory = $False)]
    [string]$osSupportTeam,

    #VRA Params
    $username,
    $passwd,
    $key

)

#Testing Parameters
<# -subscriptionName "sub1" -vmName "" -OS "2019-Datacenter" `
-alwaysOn "False" -powerOnTime 7 -powerOffTime 19 -rg "" `
-virtualNetworkName "" -subnetName "" `
-vmSize "Standard_B2ms" -location "eastus" -domainName "" -domainUsername "" `
-ouPath "OU=AZURE,OU=Prod,OU=nameofourwindowserverteam,OU=nameoftheou,DC=nameofourdc,DC=nameofourcompany,DC=net" `
-appId "" -EnvPrefix "DEV" -timeZone "Eastern Standard Time" -OSSupportTeam "" #>

try {

    #Import ECS Modules
    Import-Module $PSScriptRoot\..\..\Modules\ECSBasicUtilities -DisableNameChecking
    Import-Module $PSScriptRoot\..\..\Modules\ECSAzureResources -DisableNameChecking


    #Import Splunk Library
    Import-Module -name "\\path\to\modulesinternal\Splunk.Internal"
	
    #Setting up logging object
    $logMessage = @{
        params  = @{}
        details = @{}
        message = $null
    }

    #Setting parameters for Splunk logging
    $logMessage.params["subscriptionName"] = $subscriptionName
    $logMessage.params["vmName"] = $vmName
    $logMessage.params["OS"] = $OS
    $logMessage.params["alwaysOn"] = $alwaysOn
    $logMessage.params["powerOnTime"] = $powerOnTime
    $logMessage.params["powerOffTime"] = $powerOffTime
    $logMessage.params["rg"] = $rg
    $logMessage.params["virtualNetworkName"] = $virtualNetworkName
    $logMessage.params["subnetName"] = $subnetName
    $logMessage.params["vmSize"] = $vmSize
    $logMessage.params["location"] = $location
    $logMessage.params["domainName"] = $domainName
    $logMessage.params["domainUsername"] = $domainUsername
    $logMessage.params["ouPath"] = $ouPath
    $logMessage.params["appId"] = $appId
    $logMessage.params["EnvPrefix"] = $EnvPrefix
    $logMessage.params["username"] = $username
    $logMessage.params["timeZone"] = $timeZone
    $logMessage.params["availabilitySetName"] = $availabilitySetName
    $logMessage.params["osSupportTeam"] = $osSupportTeam

    #Write to Splunk (Script Starting)
    $logMessage.message = "Create-AzWindowsManagedVM.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred

    #Gets location of Create-AzWindowsManagedVM.json file
    function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }
    $jsonTemplate = Join-Path (Get-ScriptDirectory) "Create-AzWindowsManagedVM.json"

    #Test location of Create-AzWindowsManagedVM.json (hard coded)
    #$jsonTemplate = 'Create-AzWindowsManagedVM.json'

    #Set the admin username for the box
    $adminUser = "customAdmin"

    #Generate Admin Password
    $pw = Get-RandomPassword
    $adminPasswd = ConvertTo-SecureString $pw -AsPlainText -Force

    #Switch to the target subscription
    Select-AzSubscription -Subscription $subscriptionName

    #Get subscription prefix
    $subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

    #Get location in all formats from database and only utilize the format needed within the rest of the code,(EX: Location = eastus, What gets returned is Location_Display_Name = "East US")
    $locationPrefix = Get-LocationFormats -Location $location
    $locationPrefix = $locationPrefix.Location_Prefix.ToString()

    #Get Windows Support Key Vault
    $winKV = $null
    $winKV = Get-AzKeyVault -ResourceGroupName $rg | Where-Object { $_.VaultName -like "*WIN-KV*" }

    #If Windows Support Key Vault Doesn't Exist 
    if (!$winKV) {

        #Create Windows Support Key Vault Name
        $winKVName = $SubPrefix + "-" + $locationPrefix.toUpper() + "-WIN-KV-" + $appId.ToUpper() + "-" + $EnvPrefix.ToUpper()

        #Check for Soft-Deleted Key Vault
        $checkKVSoftDelete = (Get-AzKeyVault -Name $winKVName -Location $location -InRemovedState -ErrorAction SilentlyContinue).VaultName
            
        if ($checkKVSoftDelete) {

            Undo-AzKeyVaultRemoval -ResourceGroupName $rg -VaultName $winKVName -Location $location
            $winKV = Get-AzKeyVault -ResourceGroupName $rg | Where-Object { $_.VaultName -like "*WIN-KV*" }

        } else {

            #Create new Windows Support Key Vault
            $winKV = New-AzKeyVault -Name $winKVName -ResourceGroupName $rg -Location $location -EnablePurgeProtection -EnabledForDiskEncryption -EnabledForDeployment -EnabledForTemplateDeployment -Sku Premium

            #Grant Access for Windows group
            Set-AzKeyVaultAccessPolicy -VaultName $winKV.VaultName -ObjectId "windowsadgroupobjectid" `
                -PermissionsToSecrets get, list, set, delete, recover, backup, restore -ResourceGroupName $rg;
            
            #Grant Access for VRA service account
            Set-AzKeyVaultAccessPolicy -VaultName $winKV.VaultName -ObjectId "vraserviceaccountobjectid" `
                -PermissionsToKeys decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, `
                import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, `
                restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore `
                -ResourceGroupName $rg;
        }
    }

    #Set winKV as first winKV
    $winKV = $winKV[0]

    #Set Windows VM Password (after putting VM name as all uppercase)
    $vmName = $vmName.ToUpper()
    Set-AzKeyVaultSecret -VaultName $winKV.VaultName -Name "$vmName-pw" -SecretValue $adminPasswd

    #Get MKV to use for DES
    $MKV = $null
    $MKV = Get-AzKeyVault -ResourceGroupName $rg | Where-Object { $_.VaultName -like "*MKV*" }
    $MKV = $MKV[0]

    #Check to see if DES is already created and if not create it
    $LocDES = $null
    $LocDES = Get-AzDiskEncryptionSet -ResourceGroupName $rg | Where-Object { $_.Name -like "*DES*" }
    $LocDES = $LocDES[0]
    $diskEncryptionSetId = $LocDES.Id

    #Get domain Password
    Select-AzSubscription -SubscriptionName "sub1"
    $domainPW = Get-AzKeyVaultSecret -VaultName "vrakeyvault" -Name "nameofpw"
    $domainPW = $domainPW.SecretValue
    Select-AzSubscription -SubscriptionName $subscriptionName

    #Get the vnet resource group
    $vnetResourceGroup = (Get-AzVirtualNetwork | Where-Object { $_.Name -like "*$virtualNetworkName*" }).ResourceGroupName

    #Get the recovery services vault
    $RSV = $null
    $RSV = Get-AzRecoveryServicesVault -ResourceGroupName $rg
    $RSV = $RSV[0]
    
    #Get the storage account
    $SA = $null
    $SA = Get-AzStorageAccount -ResourceGroupName $rg | Where-Object { $_.StorageAccountName -like "*001*" }
    $SA = $SA[0]

    #Check to see if Availability set name was passed from VRA
    if ($availabilitySetName) {
        $avSetFlag = "True"
    } else {
        $avSetFlag = "False"
    }

    #Modify the PowerSchedule based on alwaysOn input
    if($alwaysOn -eq "True"){
        $PowerSchedule = "AlwaysOn"
    } else {
        $PowerSchedule = "Default"
    }

    #Write to Splunk (Deployment Started)
    $logMessage.message = "Windows VM deployment started"
    Write-Splunk -message $logMessage

    #Call the Create VM Template and start VM deployment
    New-AzResourceGroupDeployment `
        -ResourceGroupName $rg `
        -TemplateFile $jsonTemplate `
        -Name "$vmName-deployment" `
        -powerSchedule $PowerSchedule `
        -powerOnTime $powerOnTime `
        -powerOffTime $powerOffTime `
        -vmName $vmName `
        -rg $rg `
        -virtualMachineSize $vmSize `
        -storageAccountName $sa.StorageAccountName `
        -recoveryServicesVaultName $rsv.Name `
        -OS $OS `
        -adminUsername $adminUser `
        -virtualNetworkName $virtualNetworkName `
        -virtualNetworkResourceGroupName $vnetResourceGroup `
        -subnetName $subnetName `
        -adminPassword $adminPasswd `
        -domainName $domainName `
        -ouPath $ouPath `
        -domainUsername $domainUsername `
        -domainPassword $domainPW `
        -diskEncryptionSetId $diskEncryptionSetId `
        -timeZone $timeZone `
        -avSetFlag $avSetFlag `
        -availabilitySetName $availabilitySetName `
        -osSupportTeam $osSupportTeam

    #Write to Splunk (Script Finished)
    $logMessage.message = "Create-AzWindowsManagedVM.ps1 script completed"
    Write-Splunk -message $logMessage

}

catch {

    $errorMessage = "An error has occured during the Create-AzWindowsManagedVM.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    Write-Output -message $logMessage -severity error
    throw $_
	
}