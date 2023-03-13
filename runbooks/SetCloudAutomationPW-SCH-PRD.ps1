<#############################################################################
 
    SetCloudAutomationPW-SCH-PRD.ps1
    AUTHORS:  Dan Kreatsoulas
    CONTRIBUTORS:
    DATE:  12/12/2022
    COMMENT: This runbook will reset the CA service account password once per month.
    VERSION HISTORY:
    1.0 - 12/12/2022 - Created
    FUTURE ENHANCEMENTS:
	
#############################################################################>

$userName = "CA"
$vault =""
$secretName = ""

try {
    Write-Output "Logging into Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

try{
    Write-Output "Generating a new password."    
	$newPassword = new-adPassword

	Write-output "Retrieving current password within $vault."
	$currentPassword = Get-AzKeyVaultSecret -VaultName $vault -Name $secretName

    Write-Output "Storing the new password within $vault."
    Set-AzKeyVaultSecret -VaultName $vault -Name $secretName -SecretValue $newPassword 

	Write-Output "Setting a new password in AD....."
	Set-ADAccountPassword -Identity $userName -OldPassword $currentPassword.secretvalue -NewPassword $newPassword

	Write-output "Password successfully set."
}
catch{
    Write-Error -Message $_.Exception
    throw $_.Exception
}




