# #############################################################################
#
# COMMENT:  This script creates and deploys an Azure Virtual Machine using the
# parameters defined below. This script is leveraged as part of the VRA flow:
# "Azure - Create RHEL Virtual Machine" 
#
# #############################################################################

#Parameters
param (

    #Azure Subscription
    [Parameter (Mandatory = $True)]
    [string]$subscriptionName,   

    #Virtual Machine / Server Name
    [Parameter (Mandatory = $True)]
    [string]$vmName,

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
    [string]$resourceGroup,

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
    [string]$location,

    #Application ID from/for Cherwell
    #Default Value for when there is no associated Application is "NOAP"
    [Parameter (Mandatory = $False)]
    [string]$appId = "NOAP",

    #Environment Prefix
    [Parameter (Mandatory = $True)]
    [string]$EnvPrefix,

    #AvailabilitySetName Prefix
    [Parameter (Mandatory = $False)]
    [string]$availabilitySetName,

    #OS Support Team
    [Parameter (Mandatory = $True)]
    [string]$osSupportTeam,

    #VRA Params
    $username,
    $passwd,
    $key 

)

#Testing Parameters
<#  -subscriptionName "" -vmName "TESTRHEL321" -alwaysOn "False" `
-powerOnTime 7 -powerOffTime 19 -resourceGroup "" `
-virtualNetworkName "" -subnetName "" `
-vmSize "Standard_B2ms" -location "eastus" -appId "" -envPrefix "DEV" -osSupportTeam "" `
-availabilitySetName "" #>

try {

    #Import Modules
    Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities -DisableNameChecking
    Import-Module $PSScriptRoot\..\..\Modules\AzureResources -DisableNameChecking

    #Test Import Modules (hardcoded)
    <#Import-Module "Modules\BasicUtilities.psm1"
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
    $logMessage.details["vmName"] = $vmName
    $logMessage.details["alwaysOn"] = $alwaysOn
    $logMessage.details["powerOnTime"] = $powerOnTime
    $logMessage.details["powerOffTime"] = $powerOffTime
    $logMessage.details["resourceGroup"] = $resourceGroup
    $logMessage.details["virtualNetworkName"] = $virtualNetworkName
    $logMessage.details["subnetName"] = $subnetName
    $logMessage.details["vmSize"] = $vmSize
    $logMessage.details["location"] = $location
    $logMessage.details["appId"] = $appId
    $logMessage.details["EnvPrefix"] = $EnvPrefix
    $logMessage.details["osSupportTeam"] = $osSupportTeam
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Create-AzRHELManagedVM.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred

    #Gets location of Create-AzRHELManagedVM.json file
    function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }
    $jsonTemplate = Join-Path (Get-ScriptDirectory) "Create-AzRHELManagedVM.json"

    #Test location of Create-AzRHELManagedVM.json (hard coded)
    #$jsonTemplate = 'templates\Create-AzRHELManagedVM.json'

    #set the admin username for the box
    $adminUser = "customadmin"

    #generate Admin PW
    $pw = Get-RandomPassword
    $adminPasswd = ConvertTo-SecureString $pw -AsPlainText -Force

    #Switch to the target subscription
    Select-AzSubscription -Subscription $subscriptionName

    $subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

    # Get location in all formats from database and only utilize the format needed within the rest of the code,(EX: Location = eastus, What gets returned is Location_Display_Name = "East US")
    $locationPrefix = Get-LocationFormats -Location $location
    $locationPrefix = $locationPrefix.Location_Prefix.ToString()

    #Get UNIX Support Key Vault
    $unixKV = Get-AzKeyVault -ResourceGroupName $resourceGroup | Where-Object { $_.VaultName -like "*UNIX-KV*" }

    #If Unix Support Key Vault Doesn't Exist 
    if (!$unixKV) {

        #Create Unix Support Key Vault Name
        $unixKVName = $SubPrefix + "-" + $locationPrefix.toUpper() + "-UNIX-KV-" + $appId.ToUpper() + "-" + $EnvPrefix.ToUpper()

        #Check for Soft-Deleted Key Vault
        $checkKVSoftDelete = (Get-AzKeyVault -Name $unixKVName -Location $location -InRemovedState -ErrorAction SilentlyContinue).VaultName
            
        if ($checkKVSoftDelete) {

            Undo-AzKeyVaultRemoval -ResourceGroupName $rg -VaultName $unixKVName -Location $location
            $unixKV = Get-AzKeyVault -ResourceGroupName $rg | Where-Object { $_.VaultName -like "*UNIX-KV*" }

        }

        else {

            #Create new Unix Support Key Vault
            $unixKV = New-AzKeyVault -Name $unixKVName -ResourceGroupName $resourceGroup -Location $location

            #write the pw to key vault
            Set-AzKeyVaultAccessPolicy -VaultName $unixKV.VaultName -ObjectId (Get-AzADGroup -SearchString "Unix Admins")[0].Id `
                -PermissionsToSecrets get, list, set, delete, recover, backup, restore -ResourceGroupName $resourceGroup;
            Set-AzKeyVaultAccessPolicy -VaultName $unixKV.VaultName -ObjectId "objectid" `
                -PermissionsToSecrets get, list, set, delete, recover, backup, restore -ResourceGroupName $resourceGroup;
            Set-AzKeyVaultAccessPolicy -VaultName $unixKV.VaultName -ObjectId "objectid" `
                -PermissionsToKeys decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, `
                import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, `
                restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore `
                -ResourceGroupName $resourceGroup;
        }
    }
    
    #Set UNIX VM Password (after putting VM name as all uppercase)
    $vmName = $vmName.ToLower()
    Set-AzKeyVaultSecret -VaultName $unixKV.VaultName -Name "$vmName-pw" -SecretValue $adminPasswd

    #Get the Base RG name to use for creation of the DES - Still need to figure out the best way to do this. (may need to create a DES for each RG in Azure and split name based on standard format or pull appID from the tags (may be wrong))
    $rgBase = $resourceGroup.split("-")[3]
    $EnvPrefix = $resourceGroup.split("-")[4]

    #Get MKV to use for DES
    $MKV = $null
    $MKV = Get-AzKeyVault -ResourceGroupName $resourceGroup | Where-Object { $_.VaultName -like "*$LocationPrefix-*" -and $_.VaultName -like "*MKV*" }

    #set KVName to the location based MKV's vault name
    $kvName = $MKV.VaultName

    #Check to see if MKV is created and if not Create new Location based MKV
    if (!$MKV) {

        #Create Location MKV as there are storage accounts in the RG and do not have a location based MKV that matches their location
        #Get All  MKV's in Resource Group
        $StdMKVName = $null
        $StdMKVName = Get-AzKeyVault -ResourceGroupName $resourceGroup | Where-Object { $_.VaultName -like "*MKV*" }
        $MKVCount = $StdMKVName.Count

        #If more than one only select the first MKV in the array
        if ($MKVCount -gt 1) {

            $StdMKVName = $StdMKVName[0]

        }

        #Get the Base MKV name by splitting on "MKV-" and then removing the "MKV-" from the beginning of the string
        $BaseMKVName = $null
        $BaseMKVName = $StdMKVName.VaultName.Split('MKV-', 2)[1]

        #Checks to make sure updated MKV Name will not be over 24 characters (The length will need to be adjusted after first full updated of all resource groups and locations (propbably won't need as it will be splitting and adding on same ammount of characters after first pass through))
        if ($BaseMKVName.Length -gt 14) {

            $BaseMKVName = ($BaseMKVName.SubString(0, 14))

        }

        #Create the New Location Based MKV Name for the Storage account that doesn't have a MKV in the region in the specified resource group
        $LocMKVName = "$SubPrefix" + "-" + "$LocationPrefix" + "-MKV-" + "$BaseMKVName"

        #Create Management Key Vault for SSE and Disk Encryption
        $MKV = New-AzKeyVault -VaultName $LocMKVName -ResourceGroupName $resourceGroup -Location $Location -EnableSoftDelete -EnabledForDiskEncryption -EnabledForDeployment -EnabledForTemplateDeployment -EnablePurgeProtection -Sku Premium
        $kvName = $MKV.VaultName
    
        #Create a new RSA Key and store in KeyVault
        $KeyOperations = 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey'
        $Expires = (Get-Date).AddYears(2).ToUniversalTime()
        $NotBefore = (Get-Date).ToUniversalTime()
        Add-AzKeyVaultKey -VaultName $LocMKVName -Name "SSE-Key" -Expires $Expires -NotBefore $NotBefore -KeyOps $KeyOperations -Destination Software
        Add-AzKeyVaultKey -VaultName $LocMKVName -Name "ADE-Key" -KeyOps $KeyOperations -Destination Software

        #Grant ISG Key Management Team and ETI Entprise Cloud Service Team Access to the Management KV and cloudautomation service account
        Set-AzKeyVaultAccessPolicy -Vaultname "$LocMKVName" -ObjectID (Get-AzADGroup -SearchString "Security AD Group")[0].Id -PermissionsToKeys  decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
        Set-AzKeyVaultAccessPolicy -Vaultname "$LocMKVName" -ObjectID (Get-AzADGroup -SearchString "Cloud Admins AD Group")[0].Id -PermissionsToKeys  decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
        Set-AzKeyVaultAccessPolicy -VaultName "$LocMKVName" -ObjectId "objectid" -PermissionsToKeys  decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
        Set-AzKeyVaultAccessPolicy -VaultName "$LocMKVName" -ObjectId "objectid" -PermissionsToKeys decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
    }

    #Check to see if DES is Already created and if not Create
    $LocDES = $null
    $LocDES = Get-AzDiskEncryptionSet -ResourceGroupName $resourceGroup | Where-Object { $_.Name -like "*$LocationPrefix-*" -and $_.Name -like "*DES*" }

    if (!$LocDES) {
        #Creates new DES name
        $desName = "$subPrefix-" + "$locationPrefix-DES-" + "$rgBase-" + "$EnvPrefix"

        #Get Key from MKV
        $Key = Get-AzKeyVaultKey -VaultName $kvName -KeyName "ADE-Key"
    
        #DES Config 
        $desConfig = New-AzDiskEncryptionSetConfig -Location $location -SourceVaultId $MKV.ResourceId -KeyUrl $Key.Key.Kid -IdentityType SystemAssigned

        #Create new DES
        $LocDES = New-AzDiskEncryptionSet -ResourceGroupName $resourceGroup -Name $desName -InputObject $desConfig
        
        Retry-PSCommand -ScriptBlock {
            Set-AzKeyVaultAccessPolicy -VaultName $kvName -ObjectId $LocDES.Identity.PrincipalId -PermissionsToKeys wrapkey, unwrapkey, get
        }

        Retry-PSCommand -ScriptBlock {
            New-AzRoleAssignment -ResourceName $kvName -ResourceGroupName $resourceGroup -ResourceType "Microsoft.KeyVault/vaults" -ObjectId $LocDES.Identity.PrincipalId -RoleDefinitionName "Reader"
        }
        
    }

    $diskEncryptionSetId = $LocDES.Id

    #get the vnet resource group
    $vnetResourceGroup = (Get-AzVirtualNetwork | Where-Object { $_.Name -like "$virtualNetworkName" }).ResourceGroupName

    #get the recovery services vault for backup and storage acct name
    $rsv = Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroup
    $sa = Get-AzStorageAccount -ResourceGroupName $resourceGroup | Where-Object { $_.StorageAccountName -like "*001*" }

    #See if Unix Administrator group has access to the current resource group
    $RGRoleAssignments = Get-AzRoleAssignment -ResourceGroupName $resourceGroup -ObjectID "roleassignmentobjectid"

    #If not Grant Unix Administrator Group Contributor Access
    if (!$RGRoleAssignments) {

        New-AzRoleAssignment -ResourceGroupName $resourceGroup -ObjectID 060a0a1e-81c7-4c52-a0c1-3be669144cf5 -RoleDefinitionName "Contributor"
        
    }

    if ($availabilitySetName) {
        $avSetFlag = "True"
    }
    else {
        $avSetFlag = "False"
    }

    #Modify the PowerSchedule based on alwaysOn input
    if($alwaysOn -eq "True"){
        $PowerSchedule = "AlwaysOn"
    }

    else{
        $PowerSchedule = "Default"
    }

    #Write to Splunk (Deployment Started)
    $logMessage.message = "RHEL VM deployment started"
    Write-Splunk -message $logMessage

    #Call the template
    New-AzResourceGroupDeployment `
        -ResourceGroupName $resourceGroup `
        -TemplateFile $jsonTemplate `
        -Name "$vmName-deployment" `
        -vmName $vmName `
        -powerSchedule $PowerSchedule `
        -powerOnTime $powerOnTime `
        -powerOffTime $powerOffTime `
        -resourceGroupFromTemplate $resourceGroup `
        -vmSize $vmSize `
        -virtualNetworkName $virtualNetworkName `
        -virtualNetworkResourceGroupName $vnetResourceGroup `
        -subnetName $subnetName `
        -adminUsername $adminUser `
        -adminPassword $adminPasswd `
        -storageAccountName $sa.StorageAccountName `
        -recoveryServicesVaultName $rsv[0].Name `
        -diskEncryptionSetId $diskEncryptionSetId `
        -avSetFlag $avSetFlag `
        -availabilitySetName $availabilitySetName `
        -osSupportTeam $osSupportTeam

    #Write to Splunk (Script Finished)
    $logMessage.message = "Create-AzRHELManagedVM.ps1 script completed"
    Write-Splunk -message $logMessage

}

catch {

    $errorMessage = "An error has occured during the Create-AzRHELManagedVM.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_ 
	
}