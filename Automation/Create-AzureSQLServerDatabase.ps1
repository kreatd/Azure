# #############################################################################
# 
# COMMENT:  This script creates and deploys an Azure PaaS SQL Server 
# and associated SQL key vault and database(s). This script is leveraged as a
# part of the VRA flow: "Azure - Create PaaS SQL Server & Database" 
#
# FUTURE ENHANCEMENTS
# Fix Database Support tag
#
# #############################################################################

#Parameters
Param(

    #Azure Subscription
    [Parameter (Mandatory = $True)]
    [string]$subscriptionName,   

    #Azure Geographic Location
    [Parameter (Mandatory = $True)]
    [string]$Location,

    #Environment Prefix
    [Parameter (Mandatory = $True)]
    [string]$EnvPrefix,

    #Application ID from/for Cherwell
    [Parameter (Mandatory = $False)]
    [string]$appId = "NOAP",

    #Cost Center of Service Owner
    [Parameter (Mandatory = $True)]
    [string]$ServOwnerCC,

    #Cost Center of Service Consumer
    [Parameter (Mandatory = $True)]
    [string]$ConsumerCC,

    #Team Name of the Consumer
    [Parameter (Mandatory = $True)]
    [string]$TeamName,

    #Technical Contact of the Consumer
    [Parameter (Mandatory = $True)]
    [string]$TechnicalContact,

    #Data Classification
    [Parameter (Mandatory = $True)]
    [string]$DataClassification,

    #Active Directory Admin on SQL Server
    [Parameter (Mandatory = $False)]
    [string]$dbAdminGroup = "DBA ADMIN GROUP",

    #Name of Collation (if specified)
    [Parameter (Mandatory = $False)]
    [string]$collationName = "SQL_Latin1_General_CP1_CI_AS",

    #Size of the SQL Server Database (if specified)
    #Default is S0
    [Parameter (Mandatory = $False)]
    [string]$serviceObjective = "S0",

    #Name of the SQL Server Database (if specified)
    [Parameter (Mandatory = $False)]
    [string]$databaseName,
    
    #Users to be added to the database
    [Parameter (Mandatory = $False)]
    [string]$dbUsers,  

    #Resource Group to be passed, if not specified
    [Parameter (Mandatory = $False)]
    [string]$resourceGroupName,

    #VRA Params
    $username,
    $passwd,
    $key

)

# Testing Parameters
<# -subscriptionName "" -location "eastus" -envPrefix "DEV" `
-appId "" -ServOwnerCC "" `
-ConsumerCC "" -TeamName "" `
-TechnicalContact " `
-dbUsers """ `
-dataClassification "BC" #>

######################################################## SET FUNCTIONS ########################################################

# Create a TDE Key Vault
function CreateTDESQLKeyVault {

    Param (

        [Parameter(Mandatory = $True)]
        [string]$rgName,

        [Parameter(Mandatory = $False)]
        [string]$appID,

        [Parameter(Mandatory = $True)]
        [string]$envPrefix,

        [Parameter(Mandatory = $True)]
        [string]$locPrefix,

        [Parameter(Mandatory = $True)]
        [string]$ServOwnerCC,

        [Parameter(Mandatory = $True)]
        [string]$subPrefix,

        [Parameter(Mandatory = $True)]
        [string]$location

    )

    Write-Output "Creating soft-delete key vault for TDE keys"
    Write-Output ""

    #Check length of appID
    if ($appId.Length -gt 6) {
        $appId = ($appId.SubString(0, 6))
    }
    
    #Set the SQL Key Vault Name
    $kvName = $subPrefix.toUpper() + "-" + $locPrefix.toUpper() + "-SQL-KV-" + $appID.ToUpper() + "-" + $envPrefix.ToUpper()

    #Check for Soft-Deleted Key Vault
    $CheckKVSoftDelete = (Get-AzKeyVault -Name $kvName -Location $location -InRemovedState -ErrorAction SilentlyContinue).VaultName
    $instanceNumber = 2
    
    #While MKV is still in removed state, increment until we get a valid name for MKV
    while ($CheckKVSoftDelete) {
    
        #Set key vault name default for loop
        $kvName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-SQL-KV-" + $appID.ToUpper() + "-" + $envPrefix.ToUpper()
        
        #Adjust key vault name using instanceNumberFormat
        $kvName = $kvName + "-" + $instanceNumber
        $CheckKVSoftDelete = (Get-AzKeyVault -Name $kvName -Location $location -InRemovedState -ErrorAction SilentlyContinue).VaultName
    
        #Increment variable for next loop through
        $instanceNumber++
    
    }

    #Create the SQL Key Vault
    $kv = New-AzKeyVault -VaultName $kvName -ResourceGroupName $rgName -Location $location -SoftDeleteRetentionInDays 90 -EnablePurgeProtection

    #Modify Service Owner Cost Center to $servOwnerCC value
    $ServOwnerCCTag = @{"Service Owner Cost Center" = $ServOwnerCC }
    Update-AzTag -ResourceId $kv.ResourceId -Tag $ServOwnerCCTag -Operation Merge

    #Add role assignment for DBA team on the SQL Key Vault
    New-AzRoleAssignment -ObjectId "insertobjectid" -RoleDefinitionName "Key Vault Contributor" -Scope $kv.ResourceId

    #Set secret permissions for DBA Team on the SQL Key Vault
    Write-Output "Assigning permissions to key vault" 
    Write-Output ""
    Set-AzKeyVaultAccessPolicy -VaultName $kv.VaultName -ObjectId "sql dba admin ad group id - blanked out for github"`
        -PermissionsToSecrets get, list, set, delete, recover, backup, restore `
        -PermissionsToKeys get, list, update, create, import, delete, recover, backup, restore `
        -ResourceGroupName $rgName;
        
    #Set local sql admin password and store in SQL Key Vault
    Write-Output "Setting local sql admin password and storing in key vault"
    Write-Output ""
    $secretName = "$appId-$envPrefix-pw"
    $pass = Get-RandomPassword
    $secpass = ConvertTo-SecureString $pass -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $kv.VaultName -Name $secretName -SecretValue $secpass

}

# Add the default  firewall rules to the SQL server
function AddSQLFirewallRules {

    Param (

        [Parameter(Mandatory = $True)]
        [string]$rgName,

        [Parameter(Mandatory = $True)]
        [string]$envPrefix,

        [Parameter(Mandatory = $True)]
        [string]$appID
        
    )

    #Find the SQL Server
    $azSqlServerName = (Get-AzSqlServer -ResourceGroupName $rgName | Where-Object { $_.ServerName -like "*-sql-srv-*" + "$appID" + "-" + "$envPrefix" }).ServerName

    #Add the MSPeering NAT Addresses
    New-AzSqlServerFirewallRule -ResourceGroupName $rgName -ServerName $azSqlServerName `
        -FirewallRuleName "firenamename" -StartIpAddress "startingip" -EndIpAddress "endip"



}

# Create the Azure SQL Server
function CreateAzureSQLServer {
    #Obtain Parameters
    Param (
 
        #Azure Subscription
        [Parameter (Mandatory = $True)]
        [string]$subscriptionName,   

        [Parameter(Mandatory = $True)]
        [string]$rgName,

        [Parameter(Mandatory = $True)]
        [string]$appID,
    
        [Parameter(Mandatory = $False)]
        [string]$dbAdminGroup,
    
        [Parameter(Mandatory = $True)]
        [string]$envPrefix, 

        [Parameter(Mandatory = $True)]
        [string]$location,

        [Parameter(Mandatory = $True)]
        [string]$locPrefix,

        [Parameter(Mandatory = $True)]
        [string]$subPrefix,

        [Parameter(Mandatory = $True)]
        [string]$ServOwnerCC,

        [Parameter(Mandatory = $True)]
        [string]$serviceObjective,

        [Parameter(Mandatory = $False)]
        [string]$CollationName,

        [Parameter(Mandatory = $False)]
        [string]$databaseName,

        [Parameter(Mandatory = $False)]
        [string]$TeamName
    )

    #Check for SQL Key Vault
    $kv = Get-AzKeyVault -ResourceGroupName $rgName | where-object { $_.VaultName -like "*SQL-KV*" }

    #Get local sql admin creds from key-vault
    $secret = Get-AzKeyVaultSecret -VaultName $kv.VaultName | Where-Object { $_.Name -like "*$envPrefix*" + "-" + "pw" }
    $pwsecret = Get-AzKeyVaultSecret -VaultName $kv.VaultName -Name $secret.Name
    # $secpasswd = ConvertTo-SecureString $pwsecret -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ("customAdmin", $pwsecret.SecretValue)

    #Create Server Name
    $serverName = $subPrefix.ToLower() + "-" + $locPrefix.ToLower() + "-sql-srv-" + $appId.ToLower() + "-" + $envPrefix.ToLower()

    #Create logical SQL server
    Write-Output "Creating logical SQL Server object:" + $serverName
    Write-Output ""
    $azSqlServer = New-AzSqlServer -ResourceGroupName $rgName -Location $location -ServerName $serverName -MinimalTlsVersion "1.2" -SqlAdministratorCredentials ($creds) -AssignIdentity

    #Grant SQL server access to key vault
    Write-Output "Granting SQL Server Access to key vault"
    Write-Output ""
    Set-AzKeyVaultAccessPolicy -VaultName $kv.VaultName -ObjectId $azSqlServer.Identity.PrincipalId -PermissionsToKeys get, WrapKey, unwrapKey
    
    #Create a new TDE key for this server in the vault
    Write-Output "Creating new TDE key"
    Write-Output ""
    $tdeKey = Add-AzKeyVaultKey -VaultName $kv.VaultName -Name "$($serverName)-TDE" -Destination Software
     
    #Add the TDE key to the SQL server
    Write-Output "Adding TDE key to SQL Server"
    Write-Output ""
    Add-AzSqlServerKeyVaultKey -ResourceGroupName $rgName -ServerName $serverName -KeyId $tdeKey.Id
     
    #Set the key to be the TDE protector
    Write-Output "Setting up TDE on the SQL Server with new TDE key"
    Write-Output ""
    Set-AzSqlServerTransparentDataEncryptionProtector -ResourceGroupName $rgName -ServerName $serverName -Type AzureKeyVault -KeyId $tdeKey.Id -Force
    
    #Set the Azure AD admin to the DBA group
    Write-Output "Setting the AD Admin Group to $dbadminGroup"
    Write-Output ""
    Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $rgName -ServerName $serverName -DisplayName $dbAdminGroup 
    
    #Add  Firewall Rules to the SQL Server
    Write-Output "Setting SQL Firewall Rules"
    Write-Output ""
    AddSQLFirewallRules -rgName $rgName -envPrefix $envPrefix -appid $appId

    #Sleep for tagging
    Start-Sleep -Seconds 60

    #Set the Database Support tag on the SQL server if owned by SQL DBA Team
    if ($dbAdminGroup -eq "name o") {        
        $dbSupportTag = @{"Database Support" = "DBA Support - SQL" }
        Update-AzTag -ResourceId $azSQLServer.ResourceId -Tag $dbSupportTag -Operation Merge

    }

    else {
        $dbSupportTag = @{"Database Support" = $TeamName }
        Update-AzTag -ResourceId $azSQLServer.ResourceId -Tag $dbSupportTag -Operation Merge     
    }

    #Modify Service Owner Cost Center to $servOwnerCC value
    $ServOwnerCCTag = @{"Service Owner Cost Center" = $ServOwnerCC }
    Update-AzTag -ResourceId $azSQLServer.ResourceId -Tag $ServOwnerCCTag -Operation Merge

    #check to see if database name has been filled out
    if ($databaseName) {

        $dbName = $databaseName
        Write-Output "Database Name Parameter passed:" $dbName
        Write-Output ""

    }

    #If not, create dbName 
    else {

        $dbName = $subPrefix.toLower() + "-" + $locPrefix.toLower() + "-sql-db-" + $appId.ToLower() + "-" + $envPrefix.ToLower()

        Write-Output "Database Name generated:" $dbName
        Write-Output ""

    }

    #Create the Azure database
    $db = New-AzSqlDatabase -ResourceGroupName $rgName -ServerName $serverName `
        -DatabaseName $dbName -RequestedServiceObjectiveName $serviceObjective `
        -CollationName $CollationName

    Write-Output "New AZ DB has been deployed:" $dbName
    Write-Output ""

    #Sleep for tagging
    Start-Sleep -Seconds 60

    #Modify Service Owner Cost Center to $servOwnerCC value
    $ServOwnerCCTag = @{"Service Owner Cost Center" = $ServOwnerCC }
    Update-AzTag -ResourceId $db.ResourceId -Tag $ServOwnerCCTag -Operation Merge

    #Set the backup retention to be 35 days
    Retry-PSCommand -ScriptBlock {
        Set-AzSqlDatabaseBackupShortTermRetentionPolicy -ResourceGroupName $rgName -ServerName $serverName -DatabaseName $dbName -RetentionDays 35
    }

    $script:databaseName = $dbName

}

# Add a database to the Azure SQL server
function CreateAzureSQLDatabase {

    Param (

        [Parameter(Mandatory = $True)]
        [string]$serverName,

        [Parameter(Mandatory = $True)]
        [string]$locPrefix,

        [Parameter(Mandatory = $True)]
        [string]$envPrefix,

        [Parameter(Mandatory = $True)]
        [string]$subPrefix,
        
        [Parameter(Mandatory = $True)]
        [string]$serviceObjective,

        [Parameter(Mandatory = $True)]
        [string]$ServOwnerCC,

        [Parameter(Mandatory = $False)]
        [string]$CollationName,

        [Parameter(Mandatory = $False)]
        [string]$databaseName

    )

    #Check to see if database name has been filled out
    if ($databaseName) {

        $dbName = $databaseName
        Write-Output "Database Name Parameter passed:" $dbName
        Write-Output ""
    }

    #If not, create database name
    else {

        $dbName = $subPrefix.toLower() + "-" + $locPrefix.toLower() + "-sql-db-" + $appId.ToLower() + "-" + $envPrefix.ToLower()
        Write-Output "Database Name generated:" $dbName
        Write-Output ""


    }

    #Check to see if this db already exists
    $checkDBName = (Get-AzSqlDatabase -ResourceGroupName $rgName -ServerName $serverName -DatabaseName $dbName -ErrorAction SilentlyContinue).DatabaseName

    #If not, loop through 
    if ($checkDBName) {

        $instanceNum = 1
        $originalDBName = $dbName
        $dbName = $originalDBName + "-" + $instanceNum
        $checkDBName = (Get-AzSqlDatabase -ResourceGroupName $rgName -ServerName $serverName -DatabaseName $dbName -ErrorAction SilentlyContinue).DatabaseName

        while ($checkDBName) {

            $instanceNum++
            $dbName = $originalDBName + "-" + $instanceNum
            $checkDBName = (Get-AzSqlDatabase -ResourceGroupName $rgName -ServerName $serverName -DatabaseName $dbName -ErrorAction SilentlyContinue).DatabaseName

            if ($checkDBName) {

                $dbName = $checkDBName

            }
        }
    }

    #Create the Azure database
    $db = New-AzSqlDatabase -ResourceGroupName $rgName -ServerName $serverName `
        -DatabaseName $dbName -RequestedServiceObjectiveName $serviceObjective `
        -CollationName $CollationName

    #Modify Service Owner Cost Center to $servOwnerCC value
    $ServOwnerCCTag = @{"Service Owner Cost Center" = $ServOwnerCC }
    Update-AzTag -ResourceId $db.ResourceId -Tag $ServOwnerCCTag -Operation Merge
    
    Write-Output "New AZ DB has been deployed:" $dbName
    Write-Output ""

    #Set the backup retention to be 35 days
    Set-AzSqlDatabaseBackupShortTermRetentionPolicy -ResourceGroupName $rgName -ServerName $serverName -DatabaseName $dbName -RetentionDays 35

    $script:databaseName = $dbName

}

function AddSQLDatabaseUsers {

    Param(

        #Name of the Resource Group
        [Parameter (Mandatory = $False)]
        [string]$rgName,

        #Name of the SQL Server
        [Parameter (Mandatory = $False)]
        [string]$serverName,

        #Name of the SQL Server Database
        [Parameter (Mandatory = $False)]
        [string]$databaseName,
    
        #Users to be added to the database
        [Parameter (Mandatory = $False)]
        [string]$dbUsers,

        #Subscription Name
        [Parameter (Mandatory = $False)]
        [string]$subscriptionName

    )

    #Check to see if any users need permissions set
    if ($dbUsers) {

        #Pull down FQDN from the SQLServer object
        $SQLServer = Get-AzSQLServer -ResourceGroupName $rgName -ServerName $serverName

        #Set the Azure Subscription Context 
        Select-AzSubscription -Subscription "sub1"
        Write-Output ""        

        #Pull down the VRA PW
        $VRAPW = (Get-AzKeyVaultSecret -VaultName "insertkvnamehere" -Name "insertnameofsecret").SecretValueText

        #Set the Azure Subscription Context for whatever Subscription the user selected
        Select-AzSubscription -Subscription $subscriptionName
        Write-Output ""

        #Create connection string
        $dbConString = "Server=tcp:$($SQLServer.FullyQualifiedDomainName),1433;Initial Catalog=$databaseName;Persist Security Info=False;User ID=username@org.edu;Password=$VRAPW;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Password;"

        #If a list of database users, split and add each
        if ($dbUsers -like "*,*") {

            #Create array from string
            $dbUsersArray = $dbUsers.Split(",")

            #For each of the users, add them to the db_owner role on the database
            foreach ($dbUser in $dbUsersArray) {

                Invoke-Sqlcmd -Query "CREATE USER [$dbUser] FROM EXTERNAL PROVIDER" -ConnectionString $dbConString
                Invoke-Sqlcmd -Query "ALTER ROLE [db_owner] ADD MEMBER [$dbUser]" -ConnectionString $dbConString

                Write-Output $dbUser "added to db_owner group on" $databaseName
                Write-Output ""

            }
        }

        #If only one user is specified, add them to the db_owner role on the database
        else {

            Invoke-Sqlcmd -Query "CREATE USER [$dbUsers] FROM EXTERNAL PROVIDER" -ConnectionString $dbConString
            Invoke-Sqlcmd -Query "ALTER ROLE [db_owner] ADD MEMBER [$dbUsers]" -ConnectionString $dbConString

            Write-Output $dbUsers "added to db_owner group on" $databaseName
            Write-Output ""

        }
    }
}


######################################################## CODE EXECUTION ########################################################

try {

    # Import Modules
    Import-Module $PSScriptRoot\..\..\Modules\BasicUtilities -DisableNameChecking
    Import-Module $PSScriptRoot\..\..\Modules\AzureResources -DisableNameChecking

    #Test Import Modules (hardcoded)
    <# Import-Module "modules\BasicUtilities.psm1"
    Import-Module "modules\AzureResources.psm1"#>

    #Import Splunk Library
    Import-Module -name "\\path\to\modules\internal\Splunk.Internal"

    #Setting up logging object
    $logMessage = @{
        params  = @{}
        details = @{}
        message = $null
    }

    #Setting parameters for Splunk logging
    $logMessage.details["subscriptionName"] = $subscriptionName
    $logMessage.details["location"] = $location
    $logMessage.details["EnvPrefix"] = $EnvPrefix
    $logMessage.details["appId"] = $appId
    $logMessage.details["ServOwnerCC"] = $ServOwnerCC
    $logMessage.details["ConsumerCC"] = $ConsumerCC
    $logMessage.details["TeamName"] = $TeamName
    $logMessage.details["TechnicalContact"] = $TechnicalContact
    $logMessage.details["dataClassification"] = $dataClassification   
    $logMessage.details["dbAdminGroup"] = $dbAdminGroup
    $logMessage.details["collationName"] = $collationName
    $logMessage.details["serviceObjective"] = $serviceObjective
    $logMessage.details["databaseName"] = $databaseName
    $logMessage.details["dbUsers"] = $dbUsers
    $logMessage.details["username"] = $username

    #Write to Splunk (Script Starting)
    $logMessage.message = "Create-AzSQLServer.ps1 script started"
    Write-Splunk -message $logMessage

    #Log into azure using encrypted PW from Parameter
    #Needs commented out when testing outside of VRA
    $aesKey = $key.split(",")
    $secpasswd = $passwd | ConvertTo-SecureString -key $aesKey
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $username, $secpasswd
    Login-AzAccount -Credential $cred

    #Set the Azure Subscription Context for whatever Subscription the user selected
    Select-AzSubscription -Subscription $subscriptionName
    Write-Output ""

    #Convert to location prefix
    $locPrefix = (Get-LocationFormats -Location $location).Location_Prefix.ToString()

    #Convert to subscription prefix
    $subPrefix = (Get-SubscriptionFormats -Subscription $subscriptionName).Subscription_Prefix.ToString()

    #If resource group name is passed, change the appId to be the one in the resource grouo
    #Used for team-based and unique resource groups (still needs to follow the standard format)
    if ($resourceGroupName) {

        $appId = $resourceGroupName -replace ".*RG-" -replace "-.*"

    }

    #Check to see if Resource Group exists
    $checkrgName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-RG-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $rgName = (Get-AzResourceGroup -ResourceGroupName $checkrgName -ErrorAction SilentlyContinue).ResourceGroupName

    #Check to see if other resources are missing
    $saName = $subPrefix.ToLower() + $locPrefix.ToLower() + "sa" + $appId.ToLower() + $envPrefix.ToLower() + "001"
    $rsvName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-RSV-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $kvName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-MKV-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $desName = $subPrefix.ToUpper() + "-" + $locPrefix.ToUpper() + "-DES-" + $appId.ToUpper() + "-" + $envPrefix.ToUpper()
    $tdekvName = $subPrefix.toUpper() + "-" + $locPrefix.toUpper() + "-SQL-KV-" + $appID.ToUpper() + "-" + $envPrefix.ToUpper()

    #Populate names of resources if they exist
    $checksaName = (Get-AzStorageAccount -ResourceGroupName $checkrgName -Name  $saName -ErrorAction SilentlyContinue).StorageAccountName
    $checkrsvName = (Get-AzRecoveryServicesVault -ResourceGroupName $checkrgName -Name $rsvName -ErrorAction SilentlyContinue).Name
    $checkkvName = (Get-AzKeyVault -ResourceGroupName $checkrgName -VaultName $kvName"*" -ErrorAction SilentlyContinue).VaultName
    $checkdesName = (Get-AzDiskEncryptionSet -ResourceGroupName $checkrgName -Name $desName -ErrorAction SilentlyContinue).Name
    $checktdekvName = (Get-AzKeyVault -ResourceGroupName $checkrgName -VaultName $tdekvName"*" -ErrorAction SilentlyContinue).VaultName

    #If resource group or resources do not exist, create them
    if (!$rgName -or !$checksaName -or !$checkrsvName -or !$checkkvName -or !$checkdesName) {

        #Create an application-based resource group
        Write-Output "Creating the Resource Group"
        Write-Output ""

        #Pass values to CreateAppRG function in AzureResources module
        #Note: We are passing in $ConsumerCC to -ServOwnerCC, as the DBA team should only be set as Service Owner Cost
        # Center on SQL resources that are supported.
        CreateAppRG -subPrefix $subPrefix -envPrefix $envPrefix -location $location `
            -locPrefix $locPrefix -ServOwnerCC $consumerCC -ConsumerCC $ConsumerCC `
            -TeamName $TeamName -TechnicalContact $TechnicalContact -dataClassification $dataClassification -appId $appId

        #Write RG Creation to Output
        $rgName = (Get-AzResourceGroup -ResourceGroupName $checkRGName).ResourceGroupName
        Write-Output "Resource Group created:" $rgName
        Write-Output ""

        #Write to Splunk (Resource Group Created)
        $logMessage.message = "Resource Group created:" + $rgName
        Write-Splunk -message $logMessage 

    }

    # If resource group exists, continue
    else {

        #Write RG Existance to Output
        Write-Output "Resource Group exists:" $rgName
        Write-Output ""

        #Write to Splunk (Resource Group Exists)
        $logMessage.message = "Resource Group exists:" + $rgName
        Write-Splunk -message $logMessage

    }

    #If TDE key vault does not exist, create it
    If (!$checktdekvName) {

        #Create a TDE Key Vault
        Write-Output "Creating the TDE SQL Key Vault"
        Write-Output ""

        CreateTDESQLKeyVault -rgName $rgName -appID $appID -envPrefix $envPrefix `
            -locPrefix $locPrefix -subPrefix $subPrefix -ServOwnerCC $ServOwnerCC -location $location

        #Write TDE SQL Key Vault Creation to Output
        $tdekvName = Get-AzKeyVault -ResourceGroupName $rgName | where-object { $_.VaultName -like "*SQL-KV*" + "*$envPrefix*" }
        Write-Output "TDE SQL Key Vault created:" $tdekvName
        Write-Output ""
        
        #Write to Splunk (TDE SQL Key Vault Created)
        $logMessage.message = "TDE SQL Key Vault Created:" + $tdekvName
        Write-Splunk -message $logMessage

    }

    else {

        #Write RG Existance to Output
        Write-Output "TDE key vault exists:" $checktdekvName
        Write-Output ""

        #Write to Splunk (TDE SQL Key Vault Exists)
        $logMessage.message = "TDE SQL Key Vault Exists:" + $tdekvName
        Write-Splunk -message $logMessage

    }

    # Check to see if the SQL server exists
    $checkSQLSrvName = $subPrefix.ToLower() + "-" + $locPrefix.ToLower() + "-sql-srv-" + $appId.ToLower() + "-" + $envPrefix.ToLower()
    $azSQLServer = (Get-AzSqlServer -ResourceGroupName $rgName -ServerName $checkSQLSrvName -ErrorAction SilentlyContinue).ServerName

    #Create a temporary exemption for the deployment
    $policyAssignment = Get-AzPolicyAssignment -Id "/providers/Microsoft.Management/managementGroups/rootofourazure/providers/Microsoft.Authorization/policyAssignments/uniqueidofpolicyassignment"
    $policyExemptionScope = $(get-azresourcegroup -ResourceGroupName $rgName).resourceId
    New-AzPolicyExemption -Name $rgName"-exemption" -PolicyAssignment $policyAssignment -Scope $policyExemptionScope -ExemptionCategory Waiver
    
    # If SQL server does not exist, create one and deploy database
    if (!$azSQLServer) {

        #Create a TDE Key Vault
        Write-Output "Creating the SQL Server"
        Write-Output ""

        #If dbAdminGroup is not set, set it to SQL Team by default
        if (!$dbAdminGroup) {

            $dbAdminGroup = "sql dba admin ad - blanked out for github"

        }

        CreateAzureSqlServer -subscriptionName $subscriptionName -rgName $rgName -appID $appID -dbAdminGroup $dbAdminGroup -envPrefix $envPrefix `
            -location $location -locPrefix $locPrefix -ServOwnerCC $ServOwnerCC -serviceObjective $serviceObjective -CollationName $CollationName `
            -subPrefix $subPrefix -databaseName $databaseName -TeamName $TeamName
        
        #Write to Splunk (SQL Server & Database Created)
        $logMessage.message = "SQL Server and Database Created:" + $checkSQLSrvName + " / " + $databaseName
        Write-Splunk -message $logMessage
        
    }

    # If SQL server exists, create the specified db
    else {

        Write-Output "SQL Server exists:" $azSQLServer
        Write-Output ""

        #Write to Splunk (SQL Server Exists)
        $logMessage.message = "SQL Server Exists:" + $azSQLServer
        Write-Splunk -message $logMessage

        #Create a SQL DB
        Write-Output "Creating the SQL Database"
        Write-Output ""

        # Check if collation has been set and if not, create the DB using the default collation
        CreateAzureSQLDatabase -serverName $azSQLServer -locPrefix $locPrefix -envPrefix $envPrefix `
            -serviceObjective $serviceObjective -subPrefix $subPrefix -ServOwnerCC $ServOwnerCC -CollationName $CollationName -databaseName $databaseName

        #Write to Splunk (SQL Database Created)
        $logMessage.message = "SQL Database Created:" + $databaseName
        Write-Splunk -message $logMessage 

    }

    #Add users to the newly created database
    AddSQLDatabaseUsers -rgName $rgName -serverName $checkSQLSrvName -databaseName $databaseName -dbUsers $dbUsers -subscriptionName $subscriptionName

    #Remove temporary exemption
    Remove-AzPolicyExemption -Scope $policyExemptionScope -Name $rgName"-exemption" -force

}

catch {

    $errorMessage = "An error has occured during the Create-AzSQLServer.ps1 script"
    $logMessage.message = $errorMessage
    $logMessage.details["StackTrace"] = $_.ScriptStackTrace
    $logMessage.details["Error"] = $_.Tostring()
    Write-Splunk -message $logMessage -severity error
    throw $_
	
}