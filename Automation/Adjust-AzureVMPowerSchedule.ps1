# #############################################################################
# 
# COMMENT:  This script adjusts the PowerTemplate tag in Azure
# that leveraged to manage VM uptime. This is leveraged in the VRA flow:
# "Azure - Adjust Power Schedule.""
#
# #############################################################################

#Parameter
param (

    #Power Schedule (Default, alwaysOn, etc.)
    [Parameter (Mandatory = $True)]
    [string]$powerSchedule,   

    #PowerOnTime (0-23)
    [Parameter (Mandatory = $False)]
    [int]$powerOnTime,

    #PowerOffTime (0-23)
    [Parameter (Mandatory = $False)]
    [int]$powerOffTime,

    #Name of Virtual Machine
    [Parameter (Mandatory = $True)]
    [string]$vmName,
    
    #Name of Resource Group
    [Parameter (Mandatory = $True)]
    [string]$rgName,

    #Name of Subscription
    [Parameter (Mandatory = $True)]
    [string]$subscriptionId,

    #VRA Params
    $username,
    $passwd,
    $key 

)

#This function takes in a Virtual Machine Object and checks for the PowerTemplate Tag
#If it is found, return true; else return false
function read-PowerTemplateTag {
    param($vm)

    $tag = $vm.Tags.PowerTemplate
    Write-Output $tag
    
    if (!$tag) {
        #PowerTemplate tag was not found, return false
        return $false
    }

    else {
        #PowerTemplate tag was found, return true
        return $true
    }
}

try {

    #Testing Parameters
    #Import Splunk Library
    Import-Module -name "\\path\to\modules\internal\Splunk.Internal"
	
    #Setting up logging object
    $logMessage = @{
        params  = @{}
        details = @{}
        message = $null
    }

    #Setting parameters for Splunk logging
    $logMessage.details["subscriptionName"] = $subscriptionName
    $logMessage.details["vmName"] = $vmName
    $logMessage.details["alwaysOn"] = $alwaysOn
    $logMessage.details["powerOnTime"] = $powerOnTime
    $logMessage.details["powerOffTime"] = $powerOffTime
    $logMessage.details["rgName"] = $rgName
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Adjust-AzureVMPowerSchedule.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred

    #Select subscription for Azure
    Select-AzSubscription -SubscriptionId $subscriptionId

    #Get VM and associated info
    $vm = Get-AzVM -ResourceGroupName $rgName -Name $vmName
    Write-Output $vm

    #Check to see if vm has the PowerTemplate tag
    if (!(read-PowerTemplateTag -vm $vm)) {
        write-output "For VM: $vm, a PowerTemplate tag was not found. Exiting..."
        exit
    }

    #If incorrect parameter is entered, write to output and exit
    if (!($powerSchedule -eq "Default" -or $powerSchedule -eq "AlwaysOff" -or `
        $powerSchedule -eq "AlwaysOn" -or $powerSchedule -eq "Retirement" -or $powerSchedule -eq "User-Managed")) {
        Write-output "Please check your 'powerSchedule' parameter! Must be one of: ['Default', 'AlwaysOn', 'AlwaysOff', `
        Retirement, User-Managed]. Exiting..."
        exit
    }

    #Get the current powerTemplate tag and its values
    $existingTag = $vm.Tags.PowerTemplate
    $existingTagValue = $existingTag | ConvertFrom-Json
    $existingPowerOnTime = $existingTagValue.PowerOnTime
    $existingPowerOffTime = $existingTagValue.PowerOffTime

    #If user selected anything but "Default", set PowerOnTime and PowerOffTime to be 0
    if ($powerSchedule -ne "Default") {
        $powerOnTime = 0
        $powerOffTime = 0
    }

    #If user selected "Default", check to see if they passed PowerOnTime and PowerOffTime
    else {
        #If powerOnTime not passed, keep as existing value
        if (!$powerOnTime) {
            $powerOnTime = $existingPowerOnTime
        }
        #If powerOffTime not passed, keep as existing value
        if (!$powerOffTime) {
            $powerOffTime = $existingPowerOffTime
        }
    }

    #Use values to create the PowerTemplate string and update the VM in Azure
    $tagString = "{`"PowerSchedule`": `"$powerSchedule`", `"PowerOnTime`": `"$powerOnTime`", `"PowerOffTime`": `"$powerOffTime`"}"
    $newTag = @{"PowerTemplate" = $tagString }
    Update-AzTag -ResourceId $vm.Id -Tag $newTag -Operation Merge

    #Write to Splunk (Script Finished)
    $logMessage.message = "Adjust-AzureVMPowerSchedule.ps1 script completed"
    Write-Splunk -message $logMessage

}

catch {

    $errorMessage = "An error has occured during the Adjust-AzureVMPowerSchedule.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_ 
	
}