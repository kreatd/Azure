#ping a VM
function fastping{
  [CmdletBinding()]
  param(
  [String]$computername = "127.0.0.1",
  [int]$delay = 5
  )

  $ping = new-object System.Net.NetworkInformation.Ping
  # see http://msdn.microsoft.com/en-us/library/system.net.networkinformation.ipstatus%28v=vs.110%29.aspx
  try {
    if ($ping.send($computername,$delay).status -ne "Success") {
      return $false;
    }
    else {
      return $true;
    }
  } catch {
    return $false;
  }
}

#get vm by location, unused but might be useful
function Get-VMsByLocation{
    param(
        [String]$location = "east"
        )
$rgs = get-azresourcegroup | where {$_.resourcegroupname -like "*$location*"}

# Get all VMs in the specified location

foreach($rg in $rgs){
$vms += Get-AzVM -ResourceGroupName $rg.ResourceGroupName
}

# Loop through each VM and get its name and private IP address
foreach ($vm in $vms) {
        $networkInterface = Get-AzNetworkInterface -ResourceGroupName $vm.ResourceGroupName -Name $vm.NetworkProfile.NetworkInterfaces[0].Id.Split('/')[-1]
        $privateIpAddress = $networkInterface.IpConfigurations[0].PrivateIpAddress
        [PSCustomObject]@{
            VMName = $vm.Name
            PrivateIpAddress = $privateIpAddress
        }
    }
}

#check availability of a VM
function Check-VMAvailability {
  param (
      [string]$VMName,
      [int]$Attempts = 5
  )

  $success = $false
  for ($i = 1; $i -le $Attempts; $i++) {
      if (fastping -computername $VMName) {
          $success = $true
          break
      }
  }
  return $success
}

$replicatedVMs = New-Object System.Collections.ArrayList
$pingOutput = @()
$result_Output = New-Object System.Collections.ArrayList

$asr = Get-AzRecoveryServicesvault | where {$_.name -eq "nameofRSV"}
Set-AzRecoveryServicesAsrVaultContext -Vault $asr
$servicefabrics = Get-AzRecoveryServicesAsrFabric
foreach($fabric in $servicefabrics){
  $protection_containers = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric
  foreach($protcontainer in $protection_containers){
    $all_asr_items += Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $protcontainer
    $prot_cont_mapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $protcontainer
    $prot_cont_mapping
  }
}

foreach($asr_item in $all_asr_items){
  $replicatedVMs.Add([PSCustomObject]@{
  'VMName' = $asr_item.RecoveryAzureVMName})
}

#keep in mind that recovered vms will have -asr in the name
#append -asr to every vm name
<#
$replicatedvms = $replicatedvms | foreach-object{$_.VMName + "-asr"}
foreach($vm in $replicatedVMs){
    write-output "pinging $vm"
    $pingOutput = Check-VMAvailability -VMName $vm
    $result_Output.Add([PSCustomObject]@{
        VMName = $vm
        Result = $pingOutput
    })
}
#>
$replicatedvms
#loop through each VM and check the ping status

foreach($vm in $replicatedVMs){
    write-output "pinging ${$vm.VMName}"
    $pingOutput = Check-VMAvailability -VMName $vm.VMName
    $result_Output.Add([PSCustomObject]@{
        VMName = $vm.VMName
        Result = $pingOutput
    })
}

#output ping results
$result_output



<#
$i=0;
Do{
foreach($vm in $Input_VMs){
    write-output "pinging ${$vm.VMName}"
    $pingOutput = fastping -computername $vm.privateipaddress
    $result_Output.Add([PSCustomObject]@{
        VMName = $vm.VMName
        Result = $pingOutput
    })
}
$i++
} while($i -lt 4)

$result = $result_output | Group-Object -Property VMName | ForEach-Object {
    $VMName = $_.VMName
    $result = $_.Group | ForEach-Object { $_.result } | Where-Object { $_ -eq $true } | Measure-Object | Select-Object -ExpandProperty Count
    [PSCustomObject]@{ VMName = $VMName; Result = $result -gt 0 }
}

$result_output | sort-object -Property Result
#>

$dnsout = @()
#pull pointer records for each vm
foreach($vm in $result_output){
  $dnsout += Resolve-DnsName -Name $vm.vmname
}

$dnsout
