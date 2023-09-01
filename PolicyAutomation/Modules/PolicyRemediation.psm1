function Write-ToDeploymentHistory {
    param (
        [Parameter(Mandatory = $true)][string]$deploymentName,
        [Parameter(Mandatory = $true)][string]$templateUri,
        [Parameter(Mandatory = $true)][object]$eventGridEvent
    )

    $policyDefinition = Get-AzPolicyDefinition -Id $eventGridEvent.data.policyDefinitionId

    $templateParameterObject = [ordered]@{
        PolicyDefinitionName     = $policyDefinition.properties.displayName
        PolicyDefinitionId       = $eventGridEvent.data.policyDefinitionId
        PolicyStandardsDocument  = $policyDefinition.Properties.Metadata.standardsDocument ? $policyDefinition.Properties.Metadata.standardsDocument : 'N/A'
        PolicyAssignmentId       = $eventGridEvent.data.policyAssignmentId
        ResourceId               = $eventGridEvent.subject
        EventType                = $eventGridEvent.eventType
        ResourceComplianceState  = $eventGridEvent.data.complianceState
        EventTime                = $eventGridEvent.eventTime
    }

    # This deployment doesn't do any resource creation/deletion.
    # It creates a new record in the deployment history of the resource group to add ease of troubleshooting for our team.
    # All changes made by the Azure function are logged in the activity log.

    $resourceGroupName = $eventGridEvent.subject.split('/')[4]

    $paramsRemediationDeployment = @{
        Name                    = $deploymentName
        ResourceGroupName       = $resourceGroupName
        TemplateUri             = $templateUri
        TemplateParameterObject = $templateParameterObject
    }

    New-AzResourceGroupDeployment @paramsRemediationDeployment
}

function Write-ToDatabase {
    param (
        [Parameter(Mandatory = $true)][string]  $sqlServer,
        [Parameter(Mandatory = $true)][string]  $sqlDatabase,
        [Parameter(Mandatory = $true)][object]  $eventGridEvent,
        [Parameter(Mandatory = $true)][bool]    $remediationTaskSucceeded,
        [Parameter(Mandatory = $true)][string]  $functionName,
        [Parameter(Mandatory = $false)][object] $exception
    )


    $policyDefinitionName = (Get-AzPolicyDefinition -Id $eventGridEvent.data.policyDefinitionId).Properties.DisplayName
    $policyDefinitionId = $eventGridEvent.data.policyDefinitionId.split('/')[-1]
    $policyAssignmentId = $eventGridEvent.data.policyAssignmentId.split('/')[-1]

    $resourceIdSections = $eventGridEvent.subject.split('/')

    $subscriptionId = $resourceIdSections[2]
    $subscriptionName = (Get-AzSubscription -SubscriptionId $subscriptionId).Name

    $resourceGroupName = $resourceIdSections[4]
    $resourceProvider = $resourceIdSections[6]  # ex. Microsoft.Storage
    $resourceName = $resourceIdSections[-1]

    $databaseAccessToken = (Get-AzAccessToken -ResourceUrl 'https://database.windows.net').Token

    if ($exception) {
        $userErrorMessage = "Error occurred on line $($exception.InvocationInfo.ScriptLineNumber): $(($exception.InvocationInfo.Line).Trim())" + [Environment]::NewLine
        $userErrorMessage += "$($exception.CategoryInfo.Activity) : $($exception.Exception.Message)"
        $userErrorMessage = $userErrorMessage.Replace("'", '') # can't pass string with single quotes into the database
    }

    try {
        $paramsInvokeSqlCmd = @{
            serverInstance = $sqlServer
            database       = $sqlDatabase
            accessToken    = $databaseAccessToken
            query          = "
                EXEC [AzurePolicy].[LogPolicyRemediationRecord]
                    @PolicyDefinitionName      = '$policyDefinitionName'
                    ,@PolicyDefinitionId        = '$policyDefinitionId'
                    ,@PolicyAssignmentId        = '$policyAssignmentId'
                    ,@SubscriptionName          = '$subscriptionName'
                    ,@ResourceGroupName         = '$resourceGroupName'
                    ,@ResourceProvider          = '$resourceProvider'
                    ,@ResourceName              = '$resourceName'
                    ,@EventType                 = '$($eventGridEvent.eventType)'
                    ,@ResourceComplianceState   = '$($eventGridEvent.data.complianceState)'
                    ,@EventTime                 = '$($eventGridEvent.eventTime)'
                    ,@RemediationTaskSucceeded  =  $($remediationTaskSucceeded -eq $true ? 1 : 0)
                    ,@ErrorMessage              = '$($userErrorMessage)'
                    ,@CreatedByFunctionApp      = '$($env:WEBSITE_SITE_NAME)'
                    ,@CreatedByFunction         = '$functionName'
            "
        }
        Invoke-Sqlcmd @paramsInvokeSqlCmd
    }
    catch {
        $dbException = $_
        $dbErrorMessage += "Error occurred on line $($dbException.InvocationInfo.ScriptLineNumber): $(($dbException.InvocationInfo.Line).Trim())"
        $dbErrorMessage += [Environment]::NewLine + [Environment]::NewLine
        $dbErrorMessage += "$($dbException.CategoryInfo.Activity) : $($dbException.Exception.Message)" + [Environment]::NewLine + [Environment]::NewLine

        if ($exception) {
            $finalErrorMessage = 'Multiple errors occurred.' + [Environment]::NewLine + $userErrorMessage + [Environment]::NewLine + $dbErrorMessage
        }
        else {
            $finalErrorMessage = $dbErrorMessage
        }

        throw $finalErrorMessage
    }
}