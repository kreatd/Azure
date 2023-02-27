# #############################################################################
# 
# CLOUD SERVICES - SCRIPT - POWERSHELL
# NAME: Set-VMZenossState.ps1
# 
# AUTHOR:  Dan Kreatsoulas
# DATE:  2/15/2022
#
# COMMENT:  This script will set the VM Production state within zenoss based
# off of your supplied input.  This runs in azure as a standalone runbook that is triggered off of a webhook
# initiated by the power_on_off-scheduler runbook.
#
# VERSION HISTORY
# 1.0 Initial script creation
# 1.1 Added ping to vm loop 3/15/2022
# FUTURE ENHANCEMENTS
# Reminder that plain text is required due to the Post limitation.  We cannot use credential or the Get method.
# A plain text header with the embedded api key was a requirement.
# #############################################################################

param
(
    [Parameter(Mandatory=$false)]
    [object] $WEBHOOKDATA
)  

$start = get-date

#$vmnames consists of the parsed json pulled from the webhook
#that was initiated by the poweron_off-scheduler runbook
$vmnames = $WEBHOOKDATA.requestbody | convertfrom-json

#This function pulls the Zenoss UID of the entered Azure VM
function Get-VMZenoUid {
    param(

        # VM Name
        [Parameter(Mandatory = $true)]
        [string]$vmname

    )

    try {

    $secretvalue = Get-AzKeyVaultSecret -VaultName "BLANKFORGITHUB" -name "BLANKFORGITHUB"
    write-output "Retrieved Key Vault Secret...."

    write-output "Creating header object...."

    ######################Necessary for the API call
    #Note that we were asked to use a Post method (also had to append the apikey to the header object) and that GET is not supported.
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

    $headers.Add("Content-Type", "application/json")

    write-output "Adding apikey to header...."
    $headers.Add("z-api-key", "$($secretvalue.secretvaluetext)")
    
    $body = "{`"action`":`"DeviceRouter`",`"method`":`"getDevices`",`"data`":[{`"params`":{`"name`":`"$vmname`",`"uid`":`"/zport/dmd/Devices/Server`"},`"keys`":[`"uid`"]}],`"tid`":1}"
    
    write-output "Sending payload to Zenoss...."
    $response = Invoke-RestMethod 'BLANKFORGITHUB' -Method 'POST' -Headers $headers -Body $body
    ######################

    }catch {
        write-output "An error has occured during the Get-VMZenoUid function"
        throw $_
        
    }
    return $response
}

#This function Sets the defind Zenoss Production state of the given Azure VM
function Set-VMZenoMaintenanceState {
    
    param(

        # VM Name
        [Parameter(Mandatory = $true)]
        [string]$vmname,
        #Zenoss device uid
        [Parameter(Mandatory = $true)]
        [string]$uid,
         [Parameter(Mandatory = $true)]
        #ZM sets the VM Zen Admin Maintenance state, Active sets the VM back to the Active state
         [ValidateSet('ZM','Active')]
         [string]$vmstate 

    )

    try {
    #within the runbook this line has no -asplaintextflag and the headers.add contains $secretvalue.secretvaluetext
    $secretvalue = Get-AzKeyVaultSecret -VaultName "BLANKFORGITHUB" -name "BLANKFORGITHUB"
    write-output "Retrieved Key Vault Secret...."

    write-output "Creating header object...."

    ######################Necessary for the API call
    #Note that we were asked to use a Post method (also had to append the apikey to the header object) and that GET is not supported.
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

    $headers.Add("Content-Type", "application/json")

    write-output "Adding apikey to header...."
    $headers.Add("z-api-key", "$($secretvalue.secretvaluetext)")
    
    if($vmstate -eq "ZM"){
        write-output "Setting $vmname's zenoss state to ZenAdmin Maintenance...."
        $body = "{`"action`":`"DeviceRouter`",`"method`":`"setProductionState`",`"data`":[{`"uids`":[`"$uid`"],`"prodState`":`"310`",`"hashcheck`":`"1`"}],`"tid`":1}"
        
    }elseif ($vmstate -eq "Active"){
        write-output "Changing $vmname's state from ZenAdmin Maintenance to Active...."
        $body = "{`"action`":`"DeviceRouter`",`"method`":`"setProductionState`",`"data`":[{`"uids`":[`"$uid`"],`"prodState`":`"1000`",`"hashcheck`":`"1`"}],`"tid`":1}"

    }
    

    write-output "Sending payload to Zenoss...."
    $response = Invoke-RestMethod 'BLANKFORGITHUB' -Method 'POST' -Headers $headers -Body $body
    ######################

    #This If statement will take in whether the parameter is ZM or Active and invoke evconsole_router to submit an event to the Zenoss event log.
	if($vmstate -eq "ZM"){	
        $body = "{`"action`":`"EventsRouter`",`"method`":`"add_event`",`"data`":[{`"summary`":`"Device placed in ZenAdmin Maintenance via Azure Automation`",`"component`":`"`",`"device`":`"$vmname`",`"severity`":`"debug`",`"evclasskey`":`"`",`"eventKey`":`"AzureMaintenance`",`"evclass`":`"/API/Azure`"}`],`"tid`":1}"
        Invoke-RestMethod 'BLANKFORGITHUB' -Method 'POST' -Headers $headers -Body $body
	}elseif($vmstate -eq "Active"){
            $body = "{`"action`":`"EventsRouter`",`"method`":`"add_event`",`"data`":[{`"summary`":`"Device removed from ZenAdmin Maintenance via Azure Automation`",`"component`":`"`",`"device`":`"$vmname`",`"severity`":`"info`",`"evclasskey`":`"`",`"eventKey`":`"AzureMaintenance`",`"evclass`":`"/API/Azure`"}`],`"tid`":1}"
       Invoke-RestMethod 'BLANKFORGITHUB' -Method 'POST' -Headers $headers -Body $body
    }

    }catch {
        Write-Output "An error has occured within the Set-VMZenoMaintenanceState function"
        throw $_
        
    }
    return $response
}

#Checks to see if a vm exists in zenoss
$zenVMs=@{}
$pingedVMs=@()
$failedtopingVMs=@()
$minutes = 20

foreach($vmname in $vmnames){

$vmUid = Get-VMZenoUid -vmname $vmname

if($vmUid.result.devices.uid){
	$zenVMs.add($vmname,$vmUid.result.devices.uid)
		}else{
		Write-output "$vmname is not being monitored in Zenoss."
	}
}

#Loop through $zenVMs Hashtable until $zenVMs.count equals $counter.count.
#$counter.count is the current count of $pingedVMs.count + $failedtopingVMs.count

do {
foreach($zenvm in $zenVMs.getEnumerator()){
	$ping = test-connection -ComputerName $zenvm.name -Quiet
        #If $zenvm pings and $pingedVMs does not contain $zenvm, add it to the $pingedVMs array.
        if($ping -and !$pingedvms.contains($zenvm.name)){
            write-output "$($zenvm.name) pinged." 
            Set-VMZenoMaintenanceState -vmname $zenvm.name -uid $zenvm.value -vmstate "Active"
            $pingedVMs += $zenvm.name
        }
        #If current time is greater than 20 minutes, force active on all of the remaining VMs
        if((get-date) -gt $start.addminutes($minutes) -and !$failedtopingVMs.Contains($zenvm.name) -and !$pingedvms.contains($zenvm.name)) {
            write-output "Timer tripped and $($zenvm.name) did not ping.... forcing the state to Active."
            Set-VMZenoMaintenanceState -vmname $zenvm.name -uid $zenvm.value -vmstate "Active"
			$failedtopingVMs += $zenvm.name
		}
	}
	$counter = $pingedVMs.count + $failedtopingVMs.count
}until ($zenVMs.count -eq $counter)