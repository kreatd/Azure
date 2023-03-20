# #############################################################################
# 
#
# COMMENT:  This script creates and removes an Azure Virtual Machine along with
# all associated resources using the parameters defined below. This script is 
# leveraged as part of the VRA flow: "Azure - Delete Virtual Machine" 
#
# #############################################################################

#Parameters
param (

    [Parameter (Mandatory = $true)]
    [string]$subscriptionID,

    [Parameter (Mandatory = $true)]
    [string]$resourceGroupName,

    [Parameter (Mandatory = $true)]
    [string]$vmName,

    #VRA Params
    $username,
    $passwd,
    $key

)

#Testing Parameters
<# -subscriptionID "" -resourceGroupName "" `
-vmName "" #>

function Remove-AzVMWithAllAssociatedObjects {
    
    param(

        # The subscription on which to work
        [Parameter(Mandatory = $true)]
        [string]$subscriptionID,

        # The Name of the resource group where the VM is deployed
        [Parameter(Mandatory = $true)]
        [string]$resourceGroupName,

        # The Name of the VM which needs to be deleted
        [Parameter(Mandatory = $true)]
        [string]$vmName
    )

    #Write to Splunk (Script Starting)
    $logMessage.message = "Remove-AzVMWithAllAssociatedObjects function started"
    Write-Splunk -message $logMessage

    #Get all resources to remove
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
    $osDisk = $vm.StorageProfile.OSDisk.Vhd.Uri
    $dataDisks = $vm.StorageProfile.DataDisks
    $nics = $vm.NetworkProfile.NetworkInterfaces
    $nics_to_delete = @()

    foreach ($nic in $nics) {
        $nics_to_delete += $nic
    }

    #Write to Splunk (Deleting Azure VM)
    $logMessage.message = "Removing VM $($vm.Name) in Resource Group $($resourceGroupName)"
    Write-Splunk -message $logMessage

    #Delete AzureVM
    Remove-AzVM -Name $vm.Name -ResourceGroupName $resourceGroupName -Force -Verbose
    
    #Write to Splunk (Deleting Boot Diagonistics Storage Container)
    $logMessage.message = "Removing Boot Diag Container"
    Write-Splunk -message $logMessage

    #grab VM.id for Container Identification
    $vmId = $vm.Properties.VmId

    #Grab Azure Storage Account associated with Resource Group and place into String object

    #Grab Boot Diagnostics storage container of VM 
    $diagContainerName = ('bootdiagnostics-{0}-{1}' -f $vm.Name.ToLower().Substring(0, 9), $vmId)

    $storageAccts = Get-AzStorageAccount -ResourceGroupName $resourceGroupName

    foreach ($account in $storageAccts) {

        $context = New-AzStorageContext -StorageAccountName $account.StorageAccountName

        $container = Get-AzStorageContainer -Name $diagContainerName -Context $context -ErrorAction 'SilentlyContinue' 

        if ($container) {
            Write-Host "Found the blob container you are searching for, deleting now."
            Remove-AzStorageContainer -Name $diagContainerName -Context $context
            Write-Host "Blob container successfully deleted"
        }
        else {
            Write-Host "The blob container you are searching for is not in this storage account"
        }
    }

    #Write to Splunk (Deleting OS Disk)
    $logMessage.message = "Removing OS disk $osDisk"
    Write-Splunk -message $logMessage

    #check for managed OS disk
    $managedDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id

    #if so, remove managed OS disk
    if ($managedDiskId) {

        $managedDisk = Get-AzResource -ResourceId $managedDiskId

        #Write to Splunk (Deleting Managed OS Disk)
        $logMessage.message = "Removing managed OS disk $($managedDisk)"
        Write-Splunk -message $logMessage

        Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $managedDisk.Name -Force
    }

    else {

        $osDiskSourceStorageAccount = ([System.Uri]$osDisk).Host.Split('.')[0]
        $osDiskSourceContainer = ([System.Uri]$osDisk).Segments[-2] -replace '/'
        $osDiskBlob = ([System.Uri]$osDisk).Segments[-1]
        $osDiskResourceGroup = Get-AzResourceGroup | Get-AzStorageAccount -Name $osDiskSourceStorageAccount -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ResourceGroupName
        $osDiskStorageKey = Get-AzStorageAccountKey -ResourceGroupName $osDiskResourceGroup -Name $osDiskSourceStorageAccount
        $osDiskContext = New-AzStorageContext -StorageAccountName $osDiskSourceStorageAccount -StorageAccountKey $osDiskStorageKey[0].Value

        #Write to Splunk (Deleting Unmanaged OS Disk)
        $logMessage.message = "Removing unmanaged OS Disk $($osDiskBlob)"
        Write-Splunk -message $logMessage

        Remove-AzStorageBlob -Blob $osDiskBlob -Container $osDiskSourceContainer -Context $osDiskContext -Force

    }

    #Write to Splunk (Deleting Data Disks)
    $logMessage.message = "Removing data disk(s) $($dataDisks)"
    Write-Splunk -message $logMessage

    #check for managed data disks
    if (!$dataDisks) {

        #Write to Splunk (No Data Disk)
        $logMessage.message = "No data disks exist on this VM"
        Write-Splunk -message $logMessage

    }

    else {

        if ($dataDisks[0].Vhd.Uri) {

            #remove unmanaged datadisks
            foreach ($dataDisk in $dataDisks) {

                $dataDiskUri = $dataDisk.Vhd.Uri
                $dataDiskSourceStorageAccount = ([System.Uri]$dataDiskUri).Host.Split('.')[0]
                $dataDiskSourceContainer = ([System.Uri]$dataDiskUri).Segments[-2] -replace '/'
                $dataDiskBlob = ([System.Uri]$dataDiskUri).Segments[-1]
                $dataDiskResourceGroup = Get-AzResourceGroup | Get-AzStorageAccount -Name $dataDiskSourceStorageAccount -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ResourceGroupName

                $dataDiskStorageKey = Get-AzStorageAccountKey -ResourceGroupName $dataDiskResourceGroup -Name $dataDiskSourceStorageAccount
                $dataDiskContext = New-AzStorageContext -StorageAccountName $dataDiskSourceStorageAccount -StorageAccountKey $dataDiskStorageKey[0].Value
                
                #Write to Splunk (Delete Data Disks)
                $logMessage.message = "Removing unmanaged data disk $($dataDiskBlob)"
                Write-Splunk -message $logMessage

                Remove-AzStorageBlob -Blob $dataDiskBlob -Container $dataDiskSourceContainer -Context $dataDiskContext -Force
            }

        }

        else {

            #remove managed datadisks
            foreach ($dataDisk in $dataDisks) {

                $dataDiskName = $dataDisk.Name
                $d = Get-AzDisk | Where-Object { $_.Name -like "*$dataDiskName*" }

                #Write to Splunk (Delete Data Disks)
                $logMessage.message = "Removing managed data disk $($dataDiskName)"
                Write-Splunk -message $logMessage

                Remove-AzDisk -ResourceGroupName $d.ResourceGroupName -DiskName $d.Name -Force

            }
        
        }

    }

    #Write to Splunk (Removing NIC) 
    foreach ($nic in $nics_to_delete) {

        $nicString = ([uri]$nic.Id).OriginalString
        $nicName = $nicString.Split("/")[-1]
        $logMessage.message = "Removing NIC $($nicName)"
        Write-Splunk -message $logMessage
    
        #Remove NIC (Write logic to check if NIC is removed)
        Remove-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $nicName -Force
    
        foreach ($ipConfig in $nic.IpConfigurations) {
            if ($null -ne $ipConfig.PublicIpAddress) {
                Remove-AzPublicIpAddress -ResourceGroupName $vm.ResourceGroupName -Name $ipConfig.PublicIpAddress.Id.Split('/')[-1] -Force
            }
            else { Write-Host "Could not find any public IP addressess attached to this NIC" $nicName }
        }  
    }

}

try {

    #Import Splunk Library
    Import-Module -name "\\path\to\modules\Splunk.Internal"
	
    #Setting up logging object
    $logMessage = @{
        params  = @{}
        details = @{}
        message = $null
    }

    #Setting parameters for Splunk logging
    $logMessage.details["subscriptionID"] = $subscriptionID
    $logMessage.details["resourceGroupName"] = $resourceGroupName
    $logMessage.details["vmName"] = $vmName
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Delete-AzVM.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred
    
    #Select Az Subscription
    Select-AzSubscription -SubscriptionId $subscriptionID
 
    #Remove VM and all associated Objects
    Remove-AzVMWithAllAssociatedObjects -subscriptionID $subscriptionID -resourceGroupName $resourceGroupName -vmName $vmName -Verbose

    #Write to Splunk (Script Ended)
    $logMessage.message = "Delete-AzVM.ps1 script ended"
    Write-Splunk -message $logMessage
    
}

catch {

    $errorMessage = "An error has occured during the Delete-AzVM.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
	
}