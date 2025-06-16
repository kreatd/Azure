
$vms = get-azvm -status | where {$_.name.Length -le 16}
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
            "Machine Name" = $vm.Name
            Nickname = $vm.tags.Role
            "IP Address" = $nic.Properties.ipConfigurations.properties.privateIPAddress
            "OS/ios/FW Version" = ($($vm.osname).Substring(0,1).ToUpper() + $($vm.osname).Substring(1))+",$($vm.osversion)"
            "Memory Size / Type" = "$($compute.memoryinmb/1024)GB / $($vm.hardwareprofile.vmsize)"
        })
    }
    elseif(($vm.StorageProfile.OsDisk.OsType -eq "Windows")) {
        [void]$vmoutput.Add([PSCustomObject]@{
            "Machine Name" = $vm.Name
            Nickname = $vm.tags.Role
            "IP Address" = $nic.Properties.ipConfigurations.properties.privateIPAddress
            "OS/ios/FW Version" = $vm.osname
            "Memory Size / Type" = "$($compute.memoryinmb/1024)GB / $($vm.hardwareprofile.vmsize)"
        })
    } else {
        write-output "$($vm.name) does not have a valid os type"
    }
}
