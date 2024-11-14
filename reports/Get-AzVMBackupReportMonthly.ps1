
connect-azaccount -identity -Environment AzureUSGovernment

#variables
$backup_Output = New-Object System.Collections.ArrayList
$vaults = Get-AzRecoveryServicesVault

#loop through each vault and obtain every item within every RSV backup container and append the values to an array.
foreach($vault in $vaults)
{
    $backup_Items = @()
    Set-AzRecoveryServicesVaultContext -Vault $vault

    $backup_Containers = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM

    foreach($backup_Container in $backup_Containers)
    {
        $backup_Items += Get-AzRecoveryServicesBackupItem -Container $backup_Container -WorkloadType AzureVM
    }

    #loop through every backup item and add the necessary values to the backup output object
    foreach($backup_Item in $backup_Items)
    {
        $backup_Output.Add([PSCustomObject]@{
        'VM Name' = $backup_Item.Name.split(";")[-1]
        'Resource Group Name' = $backup_Item.Name.split(";")[-2]
        'Last Backup Status' = $backup_Item.LastBackupStatus
        'Protection Status' = $backup_Item.ProtectionStatus
        'Last Backup Time' = $backup_Item.LastBackupTime
        'Backup Policy Name' = $backup_Item.ProtectionPolicyName
        'Recovery Services Vault' = $backup_item.policyid.split("/")[-3]
        })
    }
}

#convert the backup output to html for email formatting
$emailOutput = $backup_output | convertTo-Html

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
        background-color: darkblue;
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
    $emailOutput
    </body>
    </html>
"@

$token = GetMailTenant-EIDAccessToken

$token = $token.access_token

$emailParams = @{
"token" = $token
"emailRecipient" = ""
"fromAddress" = ""
"msgSubject" = "Azure VM Monthly Backup Report"
"htmlbody" = $emailBody
}


Send-FSCEmail @emailParams
