# #############################################################################
# COMMENT:  This script takes in a vmName, resource group name, and disk size.
# The script adds a new empty disk to the selected VM. The disk will reside in
# the same storage account and storage container as the VM's data disks.
#
# FUTURE ENHANCEMENTS
# Need to resolve issue for required Location field on New-AzDisk cmdlet. Seems
# to be a bug, says location is required but doesnt accept location param
#
# #############################################################################

#Parameters
Param (
    [Parameter (Mandatory = $True)]
    [string]$vmName,

    [Parameter (Mandatory = $True)]
    [int]$diskSizeGB,

    [Parameter (Mandatory = $True)]
    [ValidateSet('Premium_LRS', 'StandardSSD_LRS', 'Standard_LRS')]
    [string]$storageType,

    [Parameter (Mandatory = $True)]
    [string]$subscriptionName,

    [Parameter (Mandatory = $True)]
    [string]$rgName,

    #VRA Params
    $username,
    $passwd,
    $key
)

#Testing Parameters
<# -vmName "vm1" -diskSizeGB 35 -storageType "StandardSSD_LRS" `
-subscriptionName "enter sub name" -rgName "" #>

try {

    #Import Modules
    Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities
    Import-Module $PSScriptRoot\..\..\Modules\AzureResources

    #Test Import Modules (hardcoded)
    <# Import-Module "Modules\BasicUtilities.psm1"
    Import-Module "Modules\AzureResources.psm1"#>

    #Import Splunk Library
    Import-Module -name "\\path\to\module\internal\Splunk.Internal"
	
    #Setting up logging object
    $logMessage = @{
        params  = @{}
        details = @{}
        message = $null
    }

    #Setting parameters for Splunk logging
    $logMessage.details["vmName"] = $vmName
    $logMessage.details["diskSizeGB"] = $diskSizeGB
    $logMessage.details["subscriptionName"] = $subscriptionName
    $logMessage.details["storageType"] = $storageType
    $logMessage.details["rgName"] = $rgName
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Add-ManagedDataDisk.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred

    #Set Context to the subscription name 
    Select-AzSubscription -Subscription $subscriptionName

    #Get Variables from VM Object
    $virtualMachine = Get-AzVM -ResourceGroupName $rgName -Name $vmName
    $location = $virtualMachine.Location

    #Check to see if the OS Disk is using unmanaged disks as it won't allow you to attach a managed disk to a VM
    #using an unmanaged OS Disk.
    $checkOsManagedStatus = ($virtualMachine).storageprofile.osdisk.managedDisk

    If (!$checkOsManagedStatus) {

        $logMessage.message = "This VM utilizes an unmanaged OS Disk and therefore cannot use a managed data disk"
        Write-Splunk -message $logMessage
        exit

    }

    #Get subscription Prefix
    $subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

    #Get Location Prefix based on Location (EX: Location = eastus, What gets returned is Location_Display_Name = "East US")
    $locationPrefix = (Get-LocationFormats -Location $location).Location_Prefix.Tostring()

    #Get the Base RG name to use for creation of the DES - Still need to figure out the best way to do this. (may need to create a DES for each RG in Azure and split name based on standard format or pull appID from the tags (may be wrong))
    $rgBase = $rgName.split("-")[3]
    $EnvPrefix = $rgName.split("-")[4]

    #Get MKV to use for DES
    $MKV = $null
    $MKV = Get-AzKeyVault -ResourceGroupName $RGName | Where-Object { $_.VaultName -like "*$LocationPrefix-*" -and $_.VaultName -like "*MKV*" }

    #set KVName to the location based MKV's vault name
    $kvName = $MKV.VaultName

    #Check to see if MKV is created and if not Create new Location based MKV
    If (!$MKV) {

        #Create Location MKV as there are storage accounts in the RG and do not have a location based MKV that matches their location
        #Get All  MKV's in Resource Group
        $StdMKVName = $null
        $StdMKVName = Get-AzKeyVault -ResourceGroupName $RGName | Where-Object { $_.VaultName -like "*MKV*" }
        $MKVCount = $StdMKVName.Count

        #If more than one only select the first MKV in the array
        If ($MKVCount -gt 1) {

            $StdMKVName = $StdMKVName[0]

        }

        #Get the Base MKV name by splitting on "MKV-" and then removing the "MKV-" from the beginning of the string
        $BaseMKVName = $null
        $BaseMKVName = $StdMKVName.VaultName.Split('MKV-', 2)[1]

        #Checks to make sure updated MKV Name will not be over 24 characters (The length will need to be adjusted after first full updated of all resource groups and locations (propbably won't need as it will be splitting and adding on same ammount of characters after first pass through))
        If ($BaseMKVName.Length -gt 14) {

            $BaseMKVName = ($BaseMKVName.SubString(0, 14))

        }

        #Create the New Location Based MKV Name for the Storage account that doesn't have a MKV in the region in the specified resource group
        $LocMKVName = "$SubPrefix" + "-" + "$LocationPrefix" + "-MKV-" + "$BaseMKVName"

        #Create Management Key Vault for SSE and Disk Encryption
        $MKV = New-AzKeyVault -VaultName $LocMKVName -ResourceGroupName $RGName -Location $Location -EnableSoftDelete -EnabledForDiskEncryption -EnabledForDeployment -EnabledForTemplateDeployment -EnablePurgeProtection -Sku Premium
        $kvName = $MKV.VaultName
    
        #Create a new RSA Key and store in KeyVault
        $KeyOperations = 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey'
        $Expires = (Get-Date).AddYears(2).ToUniversalTime()
        $NotBefore = (Get-Date).ToUniversalTime()
        Add-AzKeyVaultKey -VaultName $LocMKVName -Name "SSE-Key" -Expires $Expires -NotBefore $NotBefore -KeyOps $KeyOperations -Destination Software
        Add-AzKeyVaultKey -VaultName $LocMKVName -Name "ADE-Key" -KeyOps $KeyOperations -Destination Software

        #Grant management teams access
        Set-AzKeyVaultAccessPolicy -Vaultname "$LocMKVName" -ObjectID (Get-AzADGroup -SearchString "Team 1")[0].Id -PermissionsToKeys  decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
        Set-AzKeyVaultAccessPolicy -Vaultname "$LocMKVName" -ObjectID (Get-AzADGroup -SearchString "Team 2")[0].Id -PermissionsToKeys  decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
        Set-AzKeyVaultAccessPolicy -VaultName "$LocMKVName" -ObjectId "objectid" -PermissionsToKeys  decrypt, encrypt, unwrapKey, wrapKey, verify, sign, get, list, update, create, import, delete, backup, restore, recover -PermissionsToSecrets get, list, set, delete, recover, backup, restore -PermissionsToCertificates get, list, update, create, import, delete, recover, backup, restore
    
    }

    #Check to see if DES is Already created and if not Create
    $LocDES = $null
    $LocDES = Get-AzDiskEncryptionSet -ResourceGroupName $RGName | Where-Object { $_.Name -like "*$LocationPrefix-*" -and $_.Name -like "*DES*" }

    If (!$LocDES) {
        #Creates new DES name
        $desName = "$subPrefix-" + "$locationPrefix-DES-" + "$rgBase-" + "$EnvPrefix"

        #Get Key from MKV
        $Key = Get-AzKeyVaultKey -VaultName $kvName -KeyName "ADE-Key"
    
        #DES Config 
        $desConfig = New-AzDiskEncryptionSetConfig -Location $location -SourceVaultId $MKV.ResourceId -KeyUrl $Key.Key.Kid -IdentityType SystemAssigned

        #Create new DES
        $LocDES = New-AzDiskEncryptionSet -ResourceGroupName $rgName -Name $desName -InputObject $desConfig
    
        Set-AzKeyVaultAccessPolicy -VaultName $kvName -ObjectId $LocDES.Identity.PrincipalId -PermissionsToKeys wrapkey, unwrapkey, get
        New-AzRoleAssignment -ResourceName $kvName -ResourceGroupName $rgName -ResourceType "Microsoft.KeyVault/vaults" -ObjectId $LocDES.Identity.PrincipalId -RoleDefinitionName "Reader"

    }

    #Get Data Disk info from from VM Object
    $DataDisks = $null
    $DataDisks = $virtualMachine.StorageProfile.DataDisks

    If ($DataDisks) {

        #Get appropriate Disk Number
        $LastDisk = $dataDisks | foreach-object { $_.Name } | sort-object | select-object -last 1
        $LastDiskNum = [int]($LastDisk).split("-")[-1]

        #Format Int - Ensures that any integer number less than three digits is returned with padded 0's in the front.
        $NewDiskNum = '{0:d3}' -f ($LastDiskNum + 1)

    }

    else {

        $NewDiskNum = "001"

    }


    #Get luns of currently attached disks and sort alphabetically 
    $Luns = ($dataDisks | foreach-object { $_.Lun } | sort-Object)
    $i = 0

    #search array of luns starting at 0 and incrementing by 1 until you find a lun that isn't in array
    While ($Luns -contains $i) {

        $i++

    }

    $NewlunID = $i 

    #Create Disk Name
    $diskName = "$vmName-data-disk-$newDiskNum"

    #Check to see if disk with this name is already created
    $CheckDiskName = Get-AzDisk | Where-Object { $_.Name -like $diskName }

    If ($CheckDiskName) {

        #Add the previously created Data Disk to the VM - (***NOTE: This Data disk is whatever size the pre-created disk was)
        Add-AzVMDataDisk -VM $virtualMachine -Name $diskName -CreateOption Attach -ManagedDiskId $checkDiskName.Id -Lun $newLunID

        #Write to Splunk that the previous disk will be utilized
        $logMessage.message = "There was a disk with the same logical name already created and the previously created disk has been attached this to the VM. NOTE: The Disk that was attached may not match the size that you requested. If you require more space, please request another datadisk"
        Write-Splunk -message $logMessage

    }

    Else {

        Add-AzVMDataDisk -VM $virtualMachine -Name $diskName -CreateOption Empty -DiskSizeInGB $diskSizeGB -StorageAccountType $storageType -Lun $NewlunID -DiskEncryptionSetId $LocDES.Id
    
    }

    #Push changes to the VM
    Update-AzVM -VM $virtualMachine -ResourceGroupName $rgName
    
}

catch {

    $errorMessage = "An error has occured during the Add-ManagedDataDisk.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
	
}