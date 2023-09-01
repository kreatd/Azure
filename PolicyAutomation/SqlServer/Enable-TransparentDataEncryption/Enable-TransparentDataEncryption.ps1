#Requires -Modules Az.Accounts, Az.KeyVault, Az.ManagedServiceIdentity, Az.Resources, Az.Sql, PolicyRemediation

param (
    [Parameter(Mandatory = $true)][object]$eventGridEvent,
    [Parameter(Mandatory = $true)][object]$triggerMetadata
)

# constants:
$remediationDeploymentName = 'EnableTDE'

$keyVaultCryptoServiceEncryptionUserRole = 'Key Vault Crypto Service Encryption User'

# global variable for logging:
$paramsDatabaseRecord = @{
    sqlServer                = $env:sqlServer
    sqlDatabase              = $env:sqlDatabase
    eventGridEvent           = $eventGridEvent
    remediationTaskSucceeded = $false
    functionName             = $triggerMetadata.FunctionName
    exception                = $null
}

if ($eventGridEvent) {

    # Setting transparent data encryption (TDE) requires other resources to be in place and configured
    # correctly. We must assume the other resources (key vault, managed identity, etc) are in
    # the same subscription as the misconfigured resource.
    $resourceId = $eventGridEvent.subject
    $subscriptionId = $eventGridEvent.topic.split('/')[2]
    try {
        $paramsSetAzContext = @{ SubscriptionId = "$subscriptionId" }
        Set-AzContext @paramsSetAzContext
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    try {
        $paramsGetResource = @{
            ResourceId       = $resourceId
            ExpandProperties = $true
        }
        $resource = Get-AzResource @paramsGetResource
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Key vault tag and key vault are guaranteed to exist. Both provisioned during subscription creation.
    # Key used for Transparent Data Encryption (TDE) may NOT exist and must be created if it doesn't.
    try {
        $paramsGetKeyVault = @{ VaultName = $resource.Tags.KeyVaultName }
        $keyVault = Get-AzKeyVault @paramsGetKeyvault

        $keyName = $resource.Name + '-TDE'
        $paramsGetKeyVaultKey = @{
            VaultName = $keyVault.VaultName
            Name      = $keyName
        }
        $key = Get-AzKeyVaultKey @paramsGetKeyVaultKey

        if (-not $key) {
            $paramsNewKeyVaultKey = @{
                VaultName   = $keyVault.VaultName
                Name        = $keyName
                Destination = 'Software'
                Size        = 2048
                KeyType     = 'RSA'
                Expires     = (Get-Date).AddYears(1)

            }
            $key = Add-AzKeyVaultKey @paramsNewKeyVaultKey

            $paramsSetKeyRotationPolicy = @{
                VaultName = $keyVault.VaultName
                Name      = $keyName
                ExpiresIn = 'P1Y' # one year from today
            }
            Set-AzKeyVaultKeyRotationPolicy @paramsSetKeyRotationPolicy
        }
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Get the user assigned managed identity for the SQL Server, if it doesn't exist, create it.
    $resourceManagedIdentityName = $resource.ResourceGroupName.Replace('RG', 'MI') + '-SQLSRV'
    try {
        $paramsGetResourceManagedIdentity = @{
            ResourceGroupName = $resource.ResourceGroupName
            Name              = $resourceManagedIdentityName
        }
        $resourceManagedIdentity = Get-AzUserAssignedIdentity @paramsGetResourceManagedIdentity
        $managedIdentityExists = $true
    }
    catch {
        $errorMessage = $_.Exception.Message.split(':')[0].Trim()
        if ($errorMessage -eq '[ResourceNotFound]') {
            $managedIdentityExists = $false
        }
        else {
            $paramsDatabaseRecord.exception = $_
            Write-ToDatabase @paramsDatabaseRecord
            throw $_.Exception.Message
        }
    }

    if ($managedIdentityExists -eq $false) {

        # Create the Managed Identity
        try {
            $paramsNewManagedIdentity = @{
                ResourceGroupName = $resource.ResourceGroupName
                Name              = $resourceManagedIdentityName
                Location          = $resource.Location
            }
            $resourceManagedIdentity = New-AzUserAssignedIdentity @paramsNewManagedIdentity
        }
        catch {
            $paramsDatabaseRecord.exception = $_
            Write-ToDatabase @paramsDatabaseRecord
            throw $_.Exception.Message
        }

        # Assign the identity to the resource
        try {
            $paramsAssignManagedIdentity = @{
                ResourceGroupName             = $resource.ResourceGroupName
                ServerName                    = $resource.Name
                AssignIdentity                = $true
                UserAssignedIdentityId        = @($resourceManagedIdentity.Id)
                IdentityType                  = 'UserAssigned'
                PrimaryUserAssignedIdentityId = $resourceManagedIdentity.Id
            }
            Set-AzSqlServer @paramsAssignManagedIdentity
        }
        catch {
            $paramsDatabaseRecord.exception = $_
            Write-ToDatabase @paramsDatabaseRecord
            throw $_.Exception.Message
        }
    }

    # Ensure the managed identity has the correct RBAC roles
    try {
        $paramsGetManagedIdentityRoleAssignments = @{
            ObjectId = $resourceManagedIdentity.PrincipalId
        }
        $roleAssignments = Get-AzRoleAssignment @paramsGetManagedIdentityRoleAssignments

        $haveRequiredRoles = $roleAssignments | Where-Object { $_.RoleDefinitionName -eq $keyVaultCryptoServiceEncryptionUserRole -and $_.Scope -eq $keyVault.ResourceId }
        if (-not $haveRequiredRoles) {
            #! managed identity the Azure function runs under needs to have permissions to assign roles!
            $paramsNewRoleAssignment = @{
                ObjectId           = $resourceManagedIdentity.PrincipalId
                Scope              = $keyVault.ResourceId
                RoleDefinitionName = $keyVaultCryptoServiceEncryptionUserRole
            }
            New-AzRoleAssignment @paramsNewRoleAssignment
        }
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # All prerequisites are met, now set up transparent data encryption
    # Note, the managed identity of our function app needs permissions to be able to do this!
    try {

        # Note: I couldn't get this to work with Set-AzSqlServerTransparentDataEncryptionProtector.
        # Complained it couldn't find the key though Set-AzSqlServer was able to, maybe a bug in the commandlet?
        $paramsUseTdeKey = @{
            ResourceGroupName = $resource.ResourceGroupName
            ServerName        = $resource.Name
            KeyId             = $key.Id
        }
        Set-AzSqlServer @paramsUseTdeKey

        $paramsAutoRotateKey = @{
            ResourceGroupName   = $resource.ResourceGroupName
            InstanceName        = $resource.Name
            KeyId               = $key.Id
            Type                = 'AzureKeyVault'
            AutoRotationEnabled = $true
            Force               = $true
        }
        Set-AzSqlInstanceTransparentDataEncryptionProtector @paramsAutoRotateKey
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Trigger a deployment in the resource group where the offending resource exists
    # This log record provides visibility to our team as well as application owners that a remediation task ran against resources in their resource group
    try {
        $paramsDeploymentHistoryRecord = @{
            deploymentName = $env:armTemplateBaseName + '-' + $remediationDeploymentName + '-' + (Get-Date -UFormat %s)
            templateUri    = $env:armTemplateBaseUri + $env:armTemplatePolicyRemediation
            eventGridEvent = $eventGridEvent
        }

        Write-ToDeploymentHistory @paramsDeploymentHistoryRecord
    }
    catch {
        $paramsDatabaseRecord.exception = $_
        Write-ToDatabase @paramsDatabaseRecord
        throw $_.Exception.Message
    }

    # Log the remediation in our team's database for internal team visibility
    try {
        $paramsDatabaseRecord.remediationTaskSucceeded = $true
        Write-ToDatabase @paramsDatabaseRecord
    }
    catch {
        # Unable to write log to database, throw an error in the Azure function, maybe setup an alert to query the function apps runtime states?
        throw $_.Exception.Message
    }

}
else {
    throw 'Event grid data received by the Azure function is null. Remediation task cannot continue, terminating process.'
}
