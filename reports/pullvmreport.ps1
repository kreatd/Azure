set-azcontext -subscriptionid ""
$vms = get-azvm -status | where-object {$_.name.Length -le 16}
$vmoutput = New-Object System.Collections.ArrayList
foreach ($vm in $vms) {
    #$networkInterface = Get-AzNetworkInterface -ResourceGroupName $vm.ResourceGroupName -Name $vm.NetworkProfile.NetworkInterfaces[0].Id.Split('/')[-1]
    #$privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress
    #test
    $nicid = ($vm.NetworkProfile.NetworkInterfaces)[0].Id
    $nic = Get-AzResource -ResourceId $nicid
    $compute = get-azvmsize -vmname $vm.name -resourcegroupname $vm.resourcegroupname | where {$_.name -eq $vm.hardwareprofile.vmsize}

    if($vm.StorageProfile.OsDisk.OsType -eq "Linux"){
        [void]$vmoutput.Add([PSCustomObject]@{
            "Environment" = $vm.Tags.Environment
            "Machine Name" = $vm.Name
            Nickname = $vm.tags.Role
            "IP Address" = $nic.Properties.ipConfigurations.properties.privateIPAddress
            "OS/ios/FW Version" = ($($vm.osname).Substring(0,1).ToUpper() + $($vm.osname).Substring(1))+",$($vm.osversion)"
            "Memory Size / Type" = "$($compute.memoryinmb/1024)GB / $($vm.hardwareprofile.vmsize)"
            "AppCode" = $vm.Tags.AppCode
        })
    }
    elseif(($vm.StorageProfile.OsDisk.OsType -eq "Windows")) {
        [void]$vmoutput.Add([PSCustomObject]@{
            "Environment" = $vm.Tags.Environment
            "Machine Name" = $vm.Name
            Nickname = $vm.tags.Role
            "IP Address" = $nic.Properties.ipConfigurations.properties.privateIPAddress
            "OS/ios/FW Version" = $vm.osname
            "Memory Size / Type" = "$($compute.memoryinmb/1024)GB / $($vm.hardwareprofile.vmsize)"
            "AppCode" = $vm.Tags.AppCode
        })
    } else {
        write-output "$($vm.name) does not have a valid os type"
    }
}



$storageaccounts = get-azstorageaccount
$storageaccountoutput = New-Object System.Collections.ArrayList
foreach ($storageAccount in $storageAccounts) {
     # Get the context of the storage account
     $context = $storageAccount.Context
    
     # Get all file shares in the storage account
     $fileshares = ""
     $filesharesizeoutput = @()
     $fileshareoutput = @()
     $fileShares = Get-AzStorageShare -Context $context  | where-object {$_.isSnapshot -like "false"}

     # Output the file share information
     if ($fileShares) {
        $fileshareoutput += "Storage Account,$($storageaccount.primaryendpoints.file),$($fileshare.name)"
         foreach ($fileShare in $fileShares) {
            $filesharesizeoutput += "$($fileshare.name),$($fileshare.quota)GB"
            $fileshareoutput += "Fileshare,$($fileshare.name)"
             Write-Output "Storage Account: $($storageAccount.StorageAccountName), File Share: $($fileShare.Name)"
         }
     } else {
         Write-Host "No file shares found in storage account: $($storageAccount.StorageAccountName)"
     }
    if($fileshareoutput) {
            [void]$storageaccountoutput.Add([PSCustomObject]@{
            "Environment" = $storageaccount.Tags.Environment
            "Machine Name" = $storageaccount.StorageAccountName
            "Nickname" = $storageaccount.tags.Role
            "IP Address" = $fileshareoutput -join ","
            "Memory Size / Type" = $filesharesizeoutput -join ","
            "AppCode" = $storageaccount.Tags.AppCode
        })
    }
     
}

########
