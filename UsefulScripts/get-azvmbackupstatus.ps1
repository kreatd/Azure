






function Compare-Objects {
    param (
        [array]$Object1,
        [array]$Object2
    )

    $filteredObject1 = $Object1 | Where-Object { $_.Length -le 16 }
    $filteredObject2 = $Object2 | Where-Object { $_.Length -le 16 }

    $result = Compare-Object $filteredObject1 $filteredObject2 -PassThru

    $uniqueItems = $result | Where-Object { $filteredObject2 -notcontains $_ }

    return $uniqueitems
}


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

connect-azaccount -identity

#Variables for output
$backup_Output = New-Object System.Collections.ArrayList
$vm_BackupJobOutput = New-Object System.Collections.ArrayList
$missing_Backups = New-Object System.Collections.ArrayList

#List Vaults
$vaults = Get-AzRecoveryServicesVault

#Loop through vaults, set context and gather containers.  Parse containers for backup items and append all items to a custom object
foreach($vault in $vaults)
{
    #refresh backup_items per vault
    $backup_Items = @()
    Set-AzRecoveryServicesVaultContext -Vault $vault

    $backup_Containers = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM

    foreach($backup_Container in $backup_Containers)
        {
            $backup_Items += Get-AzRecoveryServicesBackupItem -Container $backup_Container -WorkloadType AzureVM
        }

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

#List all VMs in Azure
$VMs = get-azvm

#Compare VM list with Backup Item List
$backup_Check = Compare-Objects -Object1 $vms.name -object2 $backup_output."VM Name"

foreach($vm in $backup_Check)
    {
        $missing_Backups.Add([PSCustomObject]@{
        'Backups Disabled' = $vm
        })
    }


$vm_BackupJobs = @()
foreach($vault in $vaults)
{
    $vm_BackupJobs += Get-AzRecoveryservicesBackupJob -vaultid $vault.id -BackupManagementType AzureVM
}

foreach($vm_BackupJob in $vm_BackupJobs)
{
    if($vm_BackupJob.status -eq "Failed")
        {
        $vm_BackupJobOutput.Add([PSCustomObject]@{
        'Backups Failed' = $vm_BackupJob.workloadname
        'VM Job Status' = $vm_BackupJob.Status
        'VM Job StartTime' = $vm_BackupJob.StartTime
        'VM Job EndTime' = $vm_BackupJob.EndTime
        'VM Job Duration' = $vm_BackupJob.Duration
        'VM Job Error Details' = $vm_BackupJob.ErrorDetails.ErrorMessage
        })
        }else{
        $vm_BackupJob
        }
}

#$missing_Backups = $missing_Backups | convertTo-Html

if($missing_Backups.count -ne 0)
{
    $missing_Backups = $missing_Backups | convertTo-Html
}else{
        write-output "There are no missing backups."
}

if($vm_BackupJobOutput.count -ne 0)
{
    $vm_BackupJobOutput = $vm_BackupJobOutput | convertTo-Html
}else{
        write-output "There are no failed backups."
}

$emailBody = @"
$Style
<html>
<body>
    $missing_Backups
    <br>
    $vm_BackupJobOutput

</body>
</html>
"@

if($backup_Check.count -ne 0 -or $vm_BackupJobOutput.count -ne 0)
    {
    $token = GetMailTenant-EIDAccessToken

    $token = $token.access_token

    $emailParams = @{
    "token" = $token
    "emailRecipient" = ""
    #"emailRecipient" = ""
    "fromAddress" = ""
    "msgSubject" = "Azure VM Backup Status Report"
    "htmlbody" = $emailBody
    }
    Send-FSCEmail @emailParams

    }else{
        write-output "There are currently no issues with Azure VM Backups in our environment."
}
