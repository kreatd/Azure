
#compare object function
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

function Enable-AzVMBackup {
    param (
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [string]$CustomBackupPolicyName
    )
    
    try {
        # Get the VMs
        $vm = Get-AzVM -Name $VMName -ErrorAction Stop

        # Get the Recovery Services Vault in the same location
        switch ($vm) {
            { $vm.tags.'Environment' -eq "devtest" -and $vm.location -eq "" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "preprod" -and $vm.location -eq "" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "prod" -and $vm.location -eq "" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "devtest" -and $vm.location -eq "" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "preprod" -and $vm.location -eq "" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "prod" -and $vm.location -eq "" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
        }
    
        # Set the vault context
        Set-AzRecoveryServicesVaultContext -Vault $vault
    
        # Determine if custom backup policy
        if ($CustomBackupPolicyName) {
        $policyName = $CustomBackupPolicyName
        }
        
        # Get the backup policy
        $backupPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $policyName -VaultId $vault.ID -ErrorAction Stop
    
        # Enable backup for the VM
        #foreach ($vm in $vms) {
        Enable-AzRecoveryServicesBackupProtection `
            -ResourceGroupName $vm.resourceGroupName `
            -Name $vm.name `
            -Policy $backupPolicy `
            -VaultId $vault.ID `
            -ErrorAction Stop
        
        Write-Output "Backup enabled successfully for VM: $($vm.Name) with policy: $policyName"
        #}
    }
    catch {
        Write-Error "Error enabling VM backup: $($_.Exception.Message)"
    }
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

connect-azaccount -identity -Environment AzureUSGovernment -subscriptionid ""

#Variables for output
$backup_Output = New-Object System.Collections.ArrayList
$vm_BackupJobOutput = New-Object System.Collections.ArrayList
$missing_Backups = New-Object System.Collections.ArrayList
$enabled_Backups = New-Object System.Collections.ArrayList

#List Vaults
$vaults = Get-AzRecoveryServicesVault

#Loop through vaults, set context and gather containers.  Parse containers for backup items and append all items to a custom object
foreach($vault in $vaults)
{
    #refresh backup_items per vault
    $backup_Items = @()
    #write-output "Setting RSV context to $($vault.name)"
    Set-AzRecoveryServicesVaultContext -Vault $vault

    $backup_Containers = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM
   
    #Remove VM objects that are greater than 16 characters (speeds the script up as well as it eliminates the serverless objects)
    $backup_Containers = $backup_Containers | Where-Object { $_.friendlyname.Length -le 16 }


    foreach($backup_Container in $backup_Containers)
        {
            #write-output "Adding $($backup_container.friendlyname) to the backup_item array."
            $backup_Items += Get-AzRecoveryServicesBackupItem -Container $backup_Container -WorkloadType AzureVM
            #start-sleep -seconds 5
        }

    foreach($backup_Item in $backup_Items)
        {
            [void]$backup_Output.Add([PSCustomObject]@{
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
#write-output "Backup Output:"
#write-output $backup_output

#List all VMs in Azure
$VMs = get-azvm
#temp filter
#$vms = $vms | where {$_.name -ne ""}
#$backup_output = $backup_output | where {$_."VM Name" -ne ""}
#Compare VM list with Backup Item List
$backup_Check = Compare-Objects -Object1 $vms.name -object2 $backup_output."VM Name"

foreach($vm in $backup_Check)
{
    #write-output "Backup Disabled on $vm"

    [void]$missing_Backups.Add([PSCustomObject]@{
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
    if($vm_BackupJob.status -eq "Failed" -and $vm_BackupJob.Operation -eq "Backup")
    {
    #write-output "Failed Backup: $vm_BackupJob"

    [void]$vm_BackupJobOutput.Add([PSCustomObject]@{
    'Backups Failed' = $vm_BackupJob.workloadname
    'VM Job Status' = $vm_BackupJob.Status
    'VM Job StartTime' = $vm_BackupJob.StartTime
    'VM Job EndTime' = $vm_BackupJob.EndTime
    'VM Job Duration' = $vm_BackupJob.Duration
    'VM Job Error Details' = $vm_BackupJob.ErrorDetails.ErrorMessage
    })
    }else{
    #$vm_BackupJob
    }
}

#$missing_Backups = $missing_Backups | convertTo-Html
#temp filter
#$vm_BackupJobOutput = $vm_BackupJobOutput | where {$_."Backups Failed" -ne "nameofvm"}

if($missing_Backups.count -ne 0)
{
    foreach($vm in $missing_backups){
        $vm = get-azvm -name $vm."Backups Disabled"
        if($vm.tags.ContainsKey("Backups") -or $vm.tags.ContainsKey("backups") ){
            write-output "$($vm.name) backups are disabled.... skipping this VM."
        }elseif($backup_Output|where {$_."VM Name" -notlike $vm.name}){
            #this double checks that there aren't backups enabled by verifying it within the container (will prevent backups from being enabled when they're already enabled
            #current fix for the subscription throttling issue.)  There's no issue if this runs without this "double check", I just thought this was annoying!
            write-output "enabling backups on $($vm.name)"
            Enable-AzVMBackup -VMName $vm.name
            [void]$enabled_Backups.Add([PSCustomObject]@{
            'Enabled Backups On' = $vm.name
            })
        }else{
            write-output "The script timed out on the storage container and believes $($vm.name) is not being backed up... just ignore this message, probably due to subscription throttling from something in the environment"
        }
    }
}else{
    write-output "There are no missing backups."
}
if($enabled_Backups.count -ne 0)
{
    $enabled_Backups = $enabled_Backups | convertTo-Html

}else{
    write-output "There are VMs to enable backups on."
}

if($vm_BackupJobOutput.count -ne 0)
{
    $vm_BackupJobOutput = $vm_BackupJobOutput | convertTo-Html
    #write-output "Failed Backups:"
    #write-outpu $vm_BackupJobOutput
}else{
    write-output "There are no failed backups."
}

$emailBody = @"
$Style
<html>
<body>
    $enabled_Backups
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

