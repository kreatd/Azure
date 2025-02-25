# Author Dan

####################################################################################################
## The goal here is to be able to gather VMs based off the extension and either delete or update them
####################################################################################################


#this function gathers the list of vms based off your input of the os, environment or extension name
function get-AzVMList{
    param(
        [string]$os, #Linux or Windows
        [string]$Environment, #DEVTEST, PREPROD, PROD
        [string]$extensionName #AzurePolicyforWindows, AzureNetworkWatcherExtension, AzureMonitorWindowsAgent
    )
    $in = Get-Clipboard
    $vms =@()
    foreach($inn in $in){
        $vms += get-azvm -name $inn
    }
    #$vms = Get-AzVM 
    $vmOutput = New-Object System.Collections.ArrayList

$VMs=$vms | select name, ResourceGroupName,  @{n="os"; e={$_.StorageProfile.OsDisk.OsType}}, @{n="Environment";e={$_.tags.'Environment'}} | where {$_.Environment -eq "$($Environment)" -and $_.os -eq "$($os)"}

foreach ($vm in $VMs) {
    $extension =@()
    if($vm.os -eq "Windows"){
        $extension = get-azvmextension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.name | select Name, ExtensionType, Publisher, TypeHandlerVersion | where {$_.name -eq "$($extensionName)"}
    }
    if($vm.os -eq "Linux"){
        $extension =get-azvmextension -ResourceGroupName $vm.ResourceGroupName -VMName $vm.name | select Name, ExtensionType, Publisher, TypeHandlerVersion | where {$_.name -eq "$($extensionName)"}
    }

    [void]$vmOutput.Add([PSCustomObject]@{
        VMName = $vm.name
        Environment = $vm.Environment
        OS = $vm.os
        ResourceGroupName = $vm.ResourceGroupName
        ExtensionName = $extension.Name
        ExtensionType = $extension.ExtensionType
        Publisher = $extension.Publisher
        TypeHandlerVersion = $extension.TypeHandlerVersion
    })
}
return $vmOutput
}

#remove extension
#example use (this will run a -whatif) remove-VMExtension -vms $list -extensionname "AzureNetworkWatcherExtension"
#This will delete the extensions: remove-VMExtension -vms $list -extensionname "AzureNetworkWatcherExtension" -delete
#Only run with the delete flag if you verified that you're working with the correct vms and deleting the correct extension!
function remove-VMExtension{
    param (
        [object]$VMs,
        [string]$extensionName,
        [switch]$delete
    )

    if ($delete) {
        # Perform the removal with -Force
        foreach($vm in $VMs){
            Remove-AzVMExtension -ResourceGroupName $vm.resourcegroupname -Name $extensionName -VMName $vm.vmname -force
        }
    } else {
        # test with -whatif
        foreach($vm in $VMs){
            Remove-AzVMExtension -ResourceGroupName $vm.resourcegroupname -Name $extensionName -VMName $vm.vmname -whatif
        }
    }
    return $extensionoutput
}


#Update Extension
#example use (this will list what VM and extensions you'll be working with) 
#update-VMExtension -vms $list -extensionname "AzureNetworkWatcherExtension" 
#-typeHandlerVersion 1.4 -extensionPublisher "Microsoft.Azure.Monitor" -ExtensionType "AzureMonitorLinuxAgent" -TypeHandlerVersion "1.33" -location "usgovtexas"
#This will delete the extensions: remove-VMExtension -vms $list -extensionname "AzureNetworkWatcherExtension" -delete
#Only run with the delete flag if you verified that you're working with the correct vms and deleting the correct extension!
function update-VMExtension{
    param (
        [object]$VMs,
        [string]$extensionName,
        $typeHandlerVersion,
        [string]$extensionpublisher,
        [string]$extensiontype,
        [string]$location,
        [switch]$update
    )

    if ($update) {
        # Perform the update with -update
        foreach($vm in $VMs){
            write-output "Updating $($vm.vmname)'s $($extensionName) Extension"
            Set-AzVMExtension -ResourceGroupName $vm.resourcegroupname `
            -Location $location `
            -VMName $vm.vmname `
            -Name $extensionName `
            -Publisher $extensionPublisher `
            -ExtensionType $extensionType `
            -TypeHandlerVersion $typeHandlerVersion `
            -EnableAutomaticUpgrade $true `

        }
    } else {
        # test with -whatif
        foreach($vm in $VMs){
            write-output "Updating $($vm.vmname)'s $($extensionName) Extension"
            Set-AzVMExtension -ResourceGroupName $vm.ResourceGroupName `
            -Location $location `
            -VMName $vm.vmname `
            -Name $extensionName `
            -Publisher $extensionPublisher `
            -ExtensionType $extensionType `
            -TypeHandlerVersion $typeHandlerVersion `
            -EnableAutomaticUpgrade $true `
            -whatif
        }
    }
    return $_
}
$list = get-AzVMList -os "Windows" -Environment "DEVTEST" -extensionname "AzureMonitorWindowsAgent"

#cut out das/openshift vms
#$VMs = $list | where {$_.VMname.length -le 16}

#If you want to remove extensions, use remove-vmextension
#remove-VMExtension -extensionname "AzureNetworkWatcherExtension" -vms $list

#if you want to update extensions, use update-vmextension
#you need to look up the newest version of the extension, the version I listed is the current version.  That value will change over time.
#update-VMExtension -vms $list -extensionname "AzureMonitorLinuxAgent" -extensionPublisher "Microsoft.Azure.Monitor" -ExtensionType "AzureMonitorLinuxAgent" -TypeHandlerVersion "1.33" -location "usgovtexas"



