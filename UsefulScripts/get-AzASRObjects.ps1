$subs = get-azsubscription #| where {$_.name -like "*"}
$all_asr_items =@()
foreach($sub in $subs){

  set-azcontext $sub.name
  $vault = Get-AzRecoveryServicesVault #| Where-Object {$_.name -like "*recovery-rsv" -or $_.name -like "*recovery01-rsv"}
  if($null -eq $vault)
  {
    write-output "no vault, skipping to next subscription..."
  }
  else
  {
  $servicefabrics = @()
  Set-AzRecoveryServicesAsrVaultContext -Vault $vault
  #$primary_fabric = Get-AzRecoveryServicesAsrFabric | Where-Object { $_.FabricSpecificDetails.Location -eq "canadacentral" }
  $servicefabrics = Get-AzRecoveryServicesAsrFabric
  foreach($fabric in $servicefabrics){
    $primary_prot_container = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric
    foreach($protcontainer in $primary_prot_container){
      $all_asr_items += Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $protcontainer
      $prot_cont_mapping = Get-AzRecoveryServicesAsrProtectionContainerMapping -ProtectionContainer $protcontainer
      $prot_cont_mapping
    }
  }
 }
}
$all_asr_items | select RecoveryAzureVMName, PrimaryProtectionContainerFriendlyName, RecoveryProtectionContainerFriendlyName, RecoveryFabricId              
