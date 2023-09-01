# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.
if ($env:MSI_SECRET) {
  Disable-AzContextAutosave -Scope Process | Out-Null
  # https://learn.microsoft.com/en-us/powershell/module/az.accounts/connect-azaccount?view=azps-10.1.0#-accountid
  Connect-AzAccount -Identity
}

# This module version is required as the later version broke the use of the Access Token.
# Every Policy Remediation Function relies on this module, importing it to save time.

$global:ErrorActionPreference = 1 # 1 means 'Stop', 'Stop is not being recognized for some reason.

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.

# This is a test of the emergency comment system.  If this was a real comment it would be conveying information.  This is only a test.
