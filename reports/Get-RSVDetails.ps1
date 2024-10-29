
$output = @()
$subscriptions = get-azsubscription

foreach($sub in $subscriptions){

    set-azcontext -Subscription $sub.id
    $vaults = Get-AzRecoveryServicesVault 

    foreach($vault in $vaults){
    
    $backupitems=Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $vault.id

        foreach($item in $backupitems){
            
            $vmname=""
            $vmname = $item.containername.split(";")[2]
            $policydetails = Get-AzRecoveryServicesBackupProtectionPolicy -VaultId $vault.id | where {$_.name -eq "DefaultPolicy"} | select Schedulepolicy, RetentionPolicy

            $x = New-Object -TypeName PSObject
            $x | Add-Member -MemberType NoteProperty -Name Subscription -Value $sub.name -Force
            $x | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $vault.resourcegroupname -Force
            $x | Add-Member -MemberType NoteProperty -Name RecoveryServiceVault -Value $vault.name -Force
            $x | Add-Member -MemberType NoteProperty -Name VMName -Value $vmname -Force
            $x | Add-Member -MemberType NoteProperty -Name PolicyName -Value $item.protectionpolicyname -Force
            $x | Add-Member -MemberType NoteProperty -Name SchedulePolicy -Value $policydetails.schedulepolicy -Force
            $x | Add-Member -MemberType NoteProperty -Name RetentionPolicy -Value $policydetails.retentionpolicy -Force

            $output += $x
        }       
    }

}

$output
<#
#Set the retention policy
$retPol = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
$retPol.DailySchedule.DurationCountInDays = 45
$retPol.WeeklySchedule.DurationCountInWeeks = 4
$retPol.MonthlySchedule.DurationCountInMonths = 6
$retPol.YearlySchedule.DurationCountInYears = 1

#Select the policy to be modified
$backPol = Get-AzRecoveryServicesBackupProtectionPolicy -Name "DefaultPolicy" -VaultID $RSV.Id
$backPol.SnapshotRetentionInDays = 3

#Adjust time for backups
$schPol = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
$schPol.ScheduleRunTimes.RemoveAt(0)
$schedule = Get-Date -Format "dddd, MMMM dd, yyyy"
$schedule = $schedule + " 02:00:00 AM"
$schedule = [DateTime]$schedule
$schedule = $schedule.ToUniversalTime()
$schPol.ScheduleRunTimes.Add($schedule)

#Sleep to allow policies to get created
Start-Sleep -Seconds 10

#Set the retention and schedule for the policy
Set-AzRecoveryServicesBackupProtectionPolicy -Policy $backPol -RetentionPolicy $retPol -SchedulePolicy $schPol -VaultID $RSV.Id
#>