<#

#>

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
            { $vm.tags.'Environment' -eq "devtest" -and $vm.location -eq "usgovtexas" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "preprod" -and $vm.location -eq "usgovtexas" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "prod" -and $vm.location -eq "usgovtexas" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "devtest" -and $vm.location -eq "usgovvirginia" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "preprod" -and $vm.location -eq "usgovvirginia" } {
                $vault = Get-AzRecoveryServicesVault -Name ""
                $policyName = ""
                break
            }
            { $vm.tags.'Environment' -eq "prod" -and $vm.location -eq "usgovvirginia" } {
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
