# #############################################################################
#
# - Script - POWERSHELL
# NAME: Modify-AppGwDiagSettings
# 
# AUTHOR(S):  Daniel Kreatsoulas
# CONTRIBUTORS(S): 
# DATE:  4/12/2023
#
# COMMENT:  This script should was created to update diagnostic settings on app gateways.
#
# 
# FUTURE ENHANCEMENTS
# 
# #############################################################################

$subscription =""
$location=""
$AppGwName=""

Function new-AppGwLogDiagSetting {
    Param (
    [Parameter(Mandatory = $True)]
    [string]$appGwName,
    [Parameter(Mandatory = $True)]
    [string]$Location

)
$locsuffix = ""
$appgw = Get-AzApplicationGateway -name $appGwName

$logSettingObj = New-AzDiagnosticSettingLogSettingsObject -Enabled $true -CategoryGroup allLogs `
-RetentionPolicyDay 0 -RetentionPolicyEnabled $false
$MetricSettingObj = New-AzDiagnosticSettingMetricSettingsObject -Enabled $true -Category AllMetrics `
-RetentionPolicyDay 0 -RetentionPolicyEnabled $false

if($Location -eq "eastus")
{
    $locSuffix = "EA"
}elseif($Location -eq "eastus2")
{
    $locSuffix = "EA2"
}elseif($Location -eq "centralus")
{
    $locSuffix = "CU"
}elseif($Location -eq "westeurope")
{
    $locSuffix = "WE"
}else
{
    write-output "location suffix is invalid"
}

New-AzDiagnosticSetting -resourceid $appgw.id -log $logSettingObj -Metric $MetricSettingObj `
-Name "AGWActivity to LOG-$locSuffix-EH-SPLK-PRD" -EventHubName "agw_log_to_splunk" `
-EventHubAuthorizationRuleId "/subscriptions/xxxxxxxx/resourcegroups/LOG-$locSuffix-RG-SPLK-PRD/providers/Microsoft.EventHub/namespaces/LOG-$locsuffix-EH-SPLK-PRD/authorizationrules/SplunkAccessPolicy"

}

Function removeAppGwDiagSetting {
    Param (
        [Parameter(Mandatory = $True)]
        [string]$appGwName
    )
$appgw = Get-AzApplicationGateway -name $appGwName
$appGwDgSetting = Get-AzDiagnosticSetting -ResourceId $appgw.id

foreach($appgwSetting in $appGwDgSetting)
    {
        Remove-AzDiagnosticSetting -ResourceId $appgw.id -name $appgwSetting.name
    }
}

set-azcontext -Subscription $subscription
remove-AppGwDiagSetting -appGwName $AppGwName
new-AppGwLogDiagSetting -appGwName $AppGwName -Location $location
