
$vmNames = @("")
$vms = @()
$endTime = Get-Date
$startTime = $endTime.AddDays(-30)

foreach($vm in $vmnames){
$VMs += Get-AzVM -Name $vm -Status
}

foreach($vm in $vms){
#refresh vars
$totalUptime = [timespan]::Zero
$totalDowntime = [timespan]::Zero

$activityLogs = Get-AzLog -resourceid $vm.id -StartTime $startTime -EndTime $endTime | Where-Object {
    ($_.OperationName -eq "Start Virtual Machine" -and $_.Status -eq "Succeeded") -or
     ($_.operationname -eq "Deallocate Virtual Machine" -and $_.Status -eq "Started")
}

# Sort the logs by EventTimestamp
$activityLogs = $activityLogs | Sort-Object EventTimestamp

# Initialize the last event timestamp
$lastEventTime = $startTime

foreach ($log in $activityLogs) {
    if ($log.OperationName -eq "Start Virtual Machine") {
        $downtime = $log.EventTimestamp - $lastEventTime
        $totalDowntime += $downtime
        $lastEventTime = $log.EventTimestamp
    } elseif ($log.OperationName -eq "Deallocate Virtual Machine") {
        $uptime = $log.EventTimestamp - $lastEventTime
        $totalUptime += $uptime
        $lastEventTime = $log.EventTimestamp
    }
}

# Calculate uptime from the last event to the end time
if ($activityLogs[-1].OperationName -eq "Start Virtual Machine") {
    $totalUptime += ($endTime - $activityLogs[-1].EventTimestamp)
} else {
    $totalDowntime += ($endTime - $activityLogs[-1].EventTimestamp)
}

# Total time period
$totalTimePeriod = $endTime - $startTime

# Calculate uptime percentage
$uptimePercentage = ($totalUptime.TotalMinutes / $totalTimePeriod.TotalMinutes) * 100

# Output the results with proper formatting
write-output $vm.name
Write-Output ("Total Uptime: " + $totalUptime)
Write-Output ("Total Downtime: " + $totalDowntime)
Write-Output ("Uptime Percentage: " + "{0:N2}" -f $uptimePercentage + "%")
}
