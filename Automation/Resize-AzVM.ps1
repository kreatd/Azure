# #############################################################################
# 
# COMMENT:  This script resizes a virtual machine in Azure. It is used as a
# part of the VRA workflow - "Resize VM"
#
# #############################################################################

param(
	[Parameter(Mandatory = $true)]
	[string]$vmName,

	[Parameter(Mandatory = $true)]
	[string]$rgName,

	[Parameter(Mandatory = $true)]
	[string]$vmSize,

	[Parameter(Mandatory = $true)]
	[string]$subscriptionId,
	
	#VRA Params
	$username,
	$passwd,
	$key
)

#Testing Data
# -vmName "" -rgName "" -vmSize "Standard_B4ms"

try {

	#Import Splunk Library
	Import-Module -name "\\path\to\modules\internal\Splunk.Internal"
	
	#Setting up logging object
	$logMessage = @{
		params  = @{}
		details = @{}
		message = $null
	}

	#Setting parameters for Splunk logging
	$logMessage.details["vmName"] = $vmName
	$logMessage.details["rgName"] = $rgName
	$logMessage.details["vmSize"] = $vmSize
	$logMessage.details["username"] = $username
	$logMessage.details["subscriptionId"] = $subscriptionId

	#Write to Splunk (Script Starting)
	$logMessage.message = "ResizeVM.ps1 script started"
	Write-Splunk -message $logMessage
	
	#Log into azure using encrypted PW from parameter
	#Needs commented out when testing outside of VRA
	$aesKey = $key.split(",")
	$secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
	$cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
	Login-AzAccount -Credential $cred

	#Set the Azure Subscription Context for whatever Subscription the user selected
	Select-AzSubscription -SubscriptionId $subscriptionId
	
	#Get the current size of the virtual machine
	$currentVMObject = (Get-AzVm -ResourceGroupName $rgName -VMName $vmName)
	$currentVMSize = $currentVMObject.HardwareProfile.VmSize

	#Log additional variables to Splunk
	$logMessage.details["currentVMObject"] = $currentVMObject
	$logMessage.details["currentVMSize"] = $currentVMSize

	#If the proposed size / new VM size (vmSize) is the same as the current, exit
	if($vmSize -eq $currentVMSize){

		#Write to Host
        Write-Host "Virtual Machine" $vmName "is already sized at" $vmSize ". Exiting script."

		#Write to Splunk (Already Sized)
        $logMessage.message = "Virtual Machine" + $vmName + "is already sized at" + $vmSize + ". Exiting script."
		Write-Splunk -message $logMessage
		
	}

	else{

		#Update the current VM to use the new vm size
		$currentVMObject.HardwareProfile.VmSize = $vmSize
		Update-AzVM -VM $currentVMObject -ResourceGroupName $rgName

	}
	
	#Write to Splunk (Script Finished)
	$logMessage.message = "ResizeVM.ps1 script completed"
	Write-Splunk -message $logMessage

}

catch {

	$errorMessage = "An error has occured during the ResizeVM.ps1 script"
	$logMessage.message = $errorMessage
	$logMessage.details["Error"] = $_.Tostring()
	Write-Splunk -message $logMessage -severity error
	throw $_
	
}