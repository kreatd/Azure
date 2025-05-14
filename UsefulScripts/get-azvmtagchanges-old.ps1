

function checkVMTagChanges(){
param($vmname)
$timeSpan = (Get-Date).AddHours(-24)

$vm= Get-AzVM -name $vmname

$vmName = $vm.Name
$vmResourceId = $vm.Id
Write-Output "Checking: $vmName"

$activityLogsArguments = @{
    resourceId = $vmResourceId
    StartTime = $timeSpan
    EndTime = (Get-Date)
}
$activityLogs = Get-AzLog @activityLogsArguments -DetailedOutput | Where-Object {$_.OperationName -like "*Write Tags*" -or $_.OperationName -like "*Update*"}
$caller = $activitylogs.Caller
$user = $caller | Select-Object -Unique

write-output "$user made changes to $vmName"

return $_
}


$test1 = New-Object System.Collections.ArrayList
$test2 = New-Object System.Collections.ArrayList
$resourceGroupName = "rg"
$storageAccountName = "sa"
$containerName = "test"
$blobName = "dantest.txt"

# Get the storage account context
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
$ctx = $storageAccount.Context

# Use Get-AzStorageBlob to get the blob reference
$blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $ctx

# Read the blob content into a variable
$reader = [System.IO.StreamReader]::new($blob.ICloudBlob.OpenReadAsync().Result)
$fileContent = $reader.ReadToEnd()
$reader.Close()

# Output the content to verify
$fileContent

$graphOutput=search-azgraph -query 'resources
| where type == "microsoft.compute/virtualmachines"
| where isnull(tags.AutoShutdownSchedule) or tags.AutoShutdownSchedule == ""
| where isnull(tags.Environment) or tags.Environment != "PROD"
| where strlen(name) <= 16
| project id, name, tags'

#cleanup data
$filecontent2= $filecontent -split "`n"
$string = $filecontent2 -replace "\s+", " " -replace "^\s+|\s+$", ""

foreach($vm in $string){
$test1.Add([PSCustomObject]@{
    'VMName' = $vm
  })
}

foreach($vm in $graphoutput.name){
$test2.Add([PSCustomObject]@{
    'VMName' = $vm
  })
}

#compare both lists
$values1=$test1.vmname
$values2=$test2.vmname

$differences = Compare-Object -ReferenceObject $values1 -DifferenceObject $values2 -PassThru
#setup a check for if the existing list has a vm that's missing from the new one... if it's missing, then ignore it.

$differences = $differences -split "`n" | Where-Object { $_ -ne "" } | ForEach-Object {$_}

if($differences){

foreach($difference in $differences){
    checkVMTagChanges -vmname $difference
}

foreach($vm in $test2){
    $fixedOutput += $vm.vmname + "`n"
}

###



# Use Get-AzStorageBlob to get the blob reference
$blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $ctx

# Convert the new content to a memory stream
$memoryStream = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.StreamWriter($memoryStream)

# Write new content to the memory stream
$writer.Write($fixedOutput)
$writer.Flush()
$memoryStream.Position = 0

# Upload the new content to the blob, overwriting the existing file
$blob.ICloudBlob.UploadFromStreamAsync($memoryStream).Wait()

# Clean up
$writer.Close()
$memoryStream.Close()


# Get the storage account context
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
$ctx = $storageAccount.Context

# Use Get-AzStorageBlob to get the blob reference
$blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $ctx

# Read the blob content into a variable
$reader = [System.IO.StreamReader]::new($blob.ICloudBlob.OpenReadAsync().Result)
$fileContent = $reader.ReadToEnd()
$reader.Close()

# Output the content to verify
$fileContent
}else{
    write-output "There have been zero autoshutdownschedule tag changes within the past 24 hours."
}
