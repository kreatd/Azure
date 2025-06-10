
Connect-azaccount -identity -Environment AzureUSGovernment

#Array of VM names
$vmNames = @("", "", "", "") 

#Get current date
$currentDate = Get-Date
$dayOfMonth = $currentDate.Day

foreach ($vmName in $vmNames) {
try {
# Get VM resource
$vm = Get-AzVM -Name $vmName
    if ($vm) {
        # Get current tags
        $res = get-azResource -resourceid $vm.id
        $tags = $res.tags
        #if day of month is between 6 and 16
        if ($dayOfMonth -ge 6 -and $dayOfMonth -le 16)
        {
            if ($tags.ContainsKey("AutoShutdownSchedule")) {
                    Write-output "Removing AutoShutdownSchedule Tag from $vmName"
                    $tags.Remove("AutoShutdownSchedule")
                    Set-AzResource -ResourceId $vm.Id -Tag $tags -Force
            } else {
                Write-output "AutoShutdownSchedule Tag does not exist on $vmName"
            }
        } else {
            if ($tags.ContainsKey("AutoShutdownSchedule")) {
                Write-output "AutoShutdownSchedule Tag already set on $vmName"
        } else {
            Write-output "Adding AutoShutdownSchedule Tag to $vmName"
            $tags.add("AutoShutdownSchedule", "11PM -> 11AM, Saturday, Sunday")
            Set-AzResource -ResourceId $vm.Id -Tag $tags -Force
            }
        }
    }
}
catch {
    Write-Error "Error processing VM $vmName : $_"
}
}
