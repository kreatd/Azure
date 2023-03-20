# #############################################################################
# 
# COMMENT:  This script queries the Cherwell CMBD and uses app id in order to
# return app name, consumer cost center, app tag, and team name. This script is 
# leveraged by various vra flows
#
# #############################################################################

#Parameters
param (

    [Parameter (Mandatory = $true)]
    [string]$appName,

    [Parameter (Mandatory = $true)]
    [string]$base,

    #VRA Params
    $username,
    $password

)

#Testing Parameters
<# -appName "Azure Utilities EA" -base "https://nameofourcompany.blanked.for.github/CherwellAPI"
#>

function get-AppInfo {
    
    param(

        $appName,
        $base,
        $username,
        $password

    )

    #Get CherwellToken from "Cherwell.ps1" using base, user, and password
    $token = get-CherwellToken -Base $Base -Username $Username -Password $Password
    $uri = "$Base" + "/api/V1/getsearchresults"
    $header = @{
        Accept         = "application/json"
        'Content-Type' = "application/json"
        Authorization  = "Bearer " + $($token.access_token)
    }
    $filters = @()
    $filters += @{
        fieldId  = "uniqueid0"
        operator = "eq"
        value    = "$appName"
    }
    $body = @{
        busObId = "uniqueid2"
        fields  = @("uniqueid1", "uniqueid3")
        filters = $filters
    }
    
    $result = invoke-restmethod -Method POST -Uri $uri -Header $header -Body $($body | convertto-json)
    write-output $result

}

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
    $logMessage.details["appName"] = $appName
    $logMessage.details["base"] = $base
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Get-InformationFromCherwellAppCI.ps1 script started"
    Write-Splunk -message $logMessage

    #Reference the Cherwell.ps1 script
    Import-Module -name "\\path\to\modules\internal\Cherwell.Internal"
    
    #Get Cherwell API Password (Testing)
    #$password = (Get-AzKeyVaultSecret -VaultName "" -Name "").SecretValueText

    #Call cherwell and get the app info
    $result = get-AppInfo -appName $appName -Base $base -Username $username -Password $password

    #set variables
    $app = $result.businessObjects[0].fields[0].value
    $cc = $result.businessObjects[0].fields[2].value
    $dept = $result.businessObjects[0].fields[1].value
    $cccName = "$cc-$dept"
    $appTag = $result.businessObjects[0].fields[3].value
    $teamName = $result.businessObjects[0].fields[4].value
  
    #create the output object containing the app Name, CC, app Tag, and Team Name
    $obj = New-Object -TypeName psObject
    $obj | Add-Member -NotePropertyName "Application Name" -NotePropertyValue $app -Force
    $obj | Add-Member -NotePropertyName "Consumer Cost Center" -NotePropertyValue $cccName -Force
    $obj | Add-Member -NotePropertyName "App Tag" -NotePropertyValue $appTag -Force
    $obj | Add-Member -NotePropertyName "Team Name" -NotePropertyValue $teamName -Force

    #Write to Splunk (Script Completed)
    $logMessage.message = "Get-InformationFromCherwellAppCI.ps1 script completed"
    Write-Splunk -message $logMessage

    #return the object to be used in other flows
    return $obj

}

catch {

    $errorMessage = "An error has occured during the Get-InformationFromCherwellAppCI.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
	
}