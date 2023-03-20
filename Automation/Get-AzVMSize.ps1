# #############################################################################
# 
# COMMENT:  This script checks for an ideal virtual machine size using CPU cores
# and RAM in Azure. It is used as a part of the VRA workflow - "Resize VM"
#
# #############################################################################

Param (
    [Parameter (Mandatory = $True)]
    [string]$cpuCores,

    [Parameter (Mandatory = $True)]
    [string]$Memory,

    [Parameter (Mandatory = $True)]
    [string]$Location,

    [Parameter (Mandatory = $True)]
    [string]$OS,

    #VRA Params
    $username,
    $passwd,	
    $key
)

try {

    #Import  Modules
    Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities
    Import-Module $PSScriptRoot\..\..\Modules\AzureResources


    
   #Import Splunk Library
   Import-Module -name "\\path\to\modules\Splunk.Internal"
	
    #Setting up logging object
    $logMessage = @{
        params  = @{}
        details = @{}
        message = $null
    }

    #Setting parameters for Splunk logging
    $logMessage.details["cpucores"] = $cpucores
    $logMessage.details["memory"] = $memory
    $logMessage.details["location"] = $location
    $logMessage.details["OS"] = $OS
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Get-AzVmSize.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd	
    Login-AzAccount -Credential $cred

    #Get proper format for $LocName variable
    $LocationName = (Get-LocationFormats -Location $Location).Location_Display_Name

    #Connection Info for  DB
    $dbServer = "prd.server.url"
    $db = "db.server.name"
    $SQLServUN = "sqlsrvlocalact"

    #Get Secret for Database Admin
    $SQLServPW = Get-AzKeyVaultSecret -VaultName "nameofkeyvault" -Name "nameofpv"

    #Query DB for a template and price with matching location, cpu, and memory 
    $AzureVMSizeQuery = Invoke-Sqlcmd -Query "SELECT TOP 1 TemplateName, PricePerHour, CPUCores, MemoryinGB FROM dbo.Azure_VMSizes WHERE TemplateLocation = '$LocationName' AND CPUCores = $CPUCores AND MemoryinGB = $Memory AND TemplateType = '$OS' ORDER BY PricePerHour ASC" -ServerInstance $dbServer -Database $db -Username $SQLServUN -Password $SQLServPW.SecretValueText
    
    #If results are returned, exact match was found
    if ($AzureVMSizeQuery) {
        Write-Output "Exact match found!"
        $logMessage.message = "Exact match found!"
        Write-Splunk -message $logMessage
    }

    #If results are not returned, search again with fuzzy logic
    else {
        $AzureVMSizeQuery = Invoke-Sqlcmd -Query "SELECT TOP 1 TemplateName, PricePerHour, CPUCores, MemoryinGB FROM dbo.Azure_VMSizes WHERE TemplateLocation = '$LocationName' AND CPUCores >= $CPUCores AND MemoryinGB >= $Memory AND TemplateType = '$OS' ORDER BY PricePerHour ASC" -ServerInstance $dbServer -Database $db -Username $SQLServUN -Password $SQLServPW.SecretValueText
        
        #If results are returned, fuzzy match was found
        if ($AzureVMSizeQuery) {
            Write-Output "Fuzzy match found!"
            $logMessage.message = "Fuzzy match found!"
            Write-Splunk -message $logMessage
        }

        #Else, no results were found and we should error out and exit the script
        else {
            throw "Cannot find a suitable template"
        }
    }

    #Set TemplateName and PricePerHour variables to pass to VM Creation script
    $TemplateName = $AzureVMSizeQuery.TemplateName
    $PricePerHour = $AzureVMSizeQuery.PricePerHour
    $memoryinGBOutput = $AzureVMSizeQuery.MemoryinGB
    $cpuCoresOutput = $AzureVMSizeQuery.CPUCores

    $logMessage.message = "Template Name is $TemplateName (CPU = $cpuCoresOutput Cores | Memory = $memoryinGBOutput GB) and cost is $PricePerHour / hour"
    Write-Splunk -message $logMessage

    #Output captured by VRA
    Write-Output $TemplateName
}

catch {
    $errorMessage = "An error has occured during the Get-AzVmSize.ps1"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
}