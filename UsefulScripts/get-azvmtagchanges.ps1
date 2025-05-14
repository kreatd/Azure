$listOfChanges = search-azgraph -query 'resourcechanges
| extend changeTime = todatetime(properties.changeAttributes.timestamp), targetResourceId = tostring(properties.targetResourceId),
changeType = tostring(properties.changeType), correlationId = properties.changeAttributes.correlationId, 
changedProperties = properties.changes, changeCount = properties.changeAttributes.changesCount
| where changeTime > ago(1d)
| where properties.targetResourceType == "microsoft.compute/virtualmachines"
| where properties.changeAttributes.changedBy == "nameofspn" or properties.changeAttributes.changedBy contains "emaildomain"
| where properties.changes contains "tags.AutoShutdownSchedule"
| project id,properties.changeAttributes.changedBy, properties.changeAttributes.timestamp, properties.changes'

$graphVMs = New-Object System.Collections.ArrayList
$changedVMs = New-Object System.Collections.ArrayList

foreach($change in $listOfChanges) {
if($null -eq $change.properties_changes."tags.AutoShutdownSchedule".newvalue -or $change.properties_changes."tags.AutoShutdownSchedule".newvalue -eq " " -or $change.properties_changes."tags.AutoShutdownSchedule".newvalue -eq "Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday")
{
    [void]$graphVMs.Add([PSCustomObject]@{
    VMName = $change.id.split("/")[8]
    ChangedBy = $change.properties_changeAttributes_changedBy
    TimeStamp = $change.properties_changeAttributes_timestamp
    NewValue = if ($null -eq $change.properties_changes."tags.AutoShutdownSchedule".newvalue){"null"}else{$change.properties_changes."tags.AutoShutdownSchedule".newvalue}
    })
 }
}

#verify that the tag is still null or missing currently in the environment
foreach($vm in $graphVMs){
    $currentValue = get-azvm -name $vm.VMName | select-object name,@{n="AutoShutdownSchedule";e={$_.tags.'AutoShutdownSchedule'}}
    if($null -eq $currentValue.AutoShutdownSchedule -or $currentValue.AutoShutdownSchedule -eq " " -or $currentValue.AutoShutdownSchedule -eq "Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday")
    {
        [void]$changedVMs.Add([PSCustomObject]@{
            VMName = $vm.VMName
            ChangedBy = $vm.changedBy
            TimeStamp = $vm.TimeStamp
            NewValue = $vm.NewValue
            })
    }
}

$graphVMs
$changedVMs

if($changedVMs){
    
$changedVMs = $changedVMs | convertTo-Html

}else{
        write-output "No tag changes."
}

$Style = @"
    
<style>
body {
    font-family: "Calibri";
    font-size: 11pt;
    color: #000000;
    }
th, td { 
    border: 1px solid #000000;
    border-collapse: collapse;
    padding: 5px;
    }
th {
    font-size: 1.2em;
    text-align: left;
    background-color: #771b61;
    color: #ffffff;
    }
td {
    color: #000000;
    }
.even { background-color: #ffffff; }
.odd { background-color: #bfbfbf; }
</style>

"@

$emailBody = @"
$Style
<html>
<body>
    $changedVMs
</body>
</html>
"@



if($changedVMs.count -ne 0)
{
$token = GetMailTenant-EIDAccessToken

$token = $token.access_token

$emailParams = @{
"token" = $token
"emailRecipient" = ""
#"emailRecipient" = ""
"fromAddress" = ""
"msgSubject" = "AutoShutdownSchedule Tag Change Alert"
"htmlbody" = $emailBody
}

Send-FSCEmail @emailParams

}else{
    write-output "No autoshutdownschedule tag changes within the past 24 hours."
}
