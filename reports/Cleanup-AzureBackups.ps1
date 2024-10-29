param (
    [Parameter(Mandatory)]
    [string] $resourcegroupname,

    [Parameter(Mandatory)]
    [string] $recoveryservicesvault

    #[Parameter(Mandatory)]
    #[string] $csvpath

)

#$vms = import-csv -path $csvpath -header "name"
#$vms = get-clipboard


$vault = Get-AzRecoveryServicesVault -ResourceGroupName $resourcegroupname -Name $recoveryservicesvault
$Container = Get-AzRecoveryServicesBackupContainer -containertype AzureVM -VaultId $vault.ID

$vms=@()
foreach($vm in $container){
    $vms+=get-azresource -name $vm.friendlyname | where {$_.ResourceType -like "*VirtualMachines"}| select name,ResourceGroupName,resourcetype
}
try {
    foreach($vm in $vms){
    write-output "Starting on VM: $vm."

    $container = Get-AzRecoveryServicesBackupContainer -vaultid $vault.id -ContainerType AzureVM
    $item=Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $vault.id | where {$_.virtualmachineid -like "*$vm*"}
    $rg=$item.containername.split(";")[1]
    write-output "Working on VM $vm within resource group $rg."

    if($item){
    Disable-AzRecoveryServicesBackupProtection -item $item -RemoveRecoveryPoints -VaultId $vault.id -force
    #-force
    write-output "Successfully Disabled VM backup $item and all recovery points have been removed."

    Get-AzRecoveryServicesVault -ResourceGroupName $rg | Set-AzRecoveryServicesVaultContext
    write-output "Successfully set-azrecoveryservicesvaultcontext on $rg's RSV"
    
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "DefaultPolicy"
    Enable-AzRecoveryServicesBackupProtection -resourcegroupname $rg -name $vm -policy $policy
    $targetrsv=($policy.id.split("/")[8])
    write-output "Successfully enabled a new backup for $vm within RSV $targetrsv"
        }else{
    write-output "Nothing for $vm."}
    }
}
catch {
    throw "An error occurred while trying to setup backups."
}




  