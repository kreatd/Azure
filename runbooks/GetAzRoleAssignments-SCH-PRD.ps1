<#############################################################################
 
  - Azure Automation Runbook 
    AUTHORS:  Dan Kreatsoulas
    CONTRIBUTORS:
    DATE:  12/19/2022
    COMMENT: This script will generate a list of role assignments that have been created within the past 24 hours.
    VERSION HISTORY:
    1.0 - 12/19/2022 - Created
    1.1 - 5/19/2023 - Added Management groups as well as converted the script to use Microsoft Graph APIs
    FUTURE ENHANCEMENTS:
    Capture role assignments at the Management group level?
#############################################################################>

# This function handles the style and body of the email
# It takes everything and puts it in an output string to be returned
function new-emailStyle_Body {
  # Creating head style
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
      background-color: #771b61;
      color: #ffffff;
      }
  td {
      color: #000000;
      }
  .even { background-color: #ffffff; }
  .odd { background-color: #bfbfbf; }
  </style>

"@

  # Creating head style and header title
  $Output = $null
  $Output = @"
  $Style
  <html>
  <body>
      <p>All,</p>

      <p>$araCount Azure Role Assignments have been created in the last 24hrs.</p>
      
  <p>$emailOutput</p>
  <br>    
      Thanks,
  <br>
      ETI 

  </body>
  </html>
"@
  return $Output
}

$subscriptions = get-azsubscription

foreach($subscription in $subscriptions){
  set-azcontext $subscription.name
  $roleAssignments += get-azRoleAssignment
}

$roleAssignments = $roleAssignments | select * -unique
$emailOutput = New-Object System.Collections.ArrayList
$managementGroups = (get-azManagementGroup).name
$timestamp = (Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$accesstoken = GetCloudAutomationSPN-AADAccessToken -scope "https://management.azure.com/"
$token = $accesstoken.access_token
$responses = @()
$headers = @{ 'Authorization' = "Bearer $token" }
$roleDefinitions = get-azRoleDefinition

foreach($managementGroup in $managementGroups) {

  $uri = "https://management.azure.com/providers/Microsoft.Management/managementGroups/$managementGroup/providers/Microsoft.Insights/eventtypes/management/values?api-version=2017-03-01-preview&`$filter=eventTimeStamp ge '$timestamp'"
  $responses += invoke-restmethod -uri $uri -method "GET" -headers $headers

}

foreach($subscription in $subscriptions) {

  $uri = "https://management.azure.com/subscriptions/$($subscription.id)/providers/Microsoft.Insights/eventtypes/management/values?api-version=2017-03-01-preview&`$filter=eventTimeStamp ge '$timestamp'"
  $responses += invoke-restmethod -uri $uri -method "GET" -headers $headers
    
}

$succeededResponses = $responses.value | Where-Object {$_.status.value -eq "Succeeded"}
$roleAssignmentActions = $succeededResponses | Where-Object {$_.Authorization.Action -eq "Microsoft.Authorization/roleAssignments/write" -or $_.Authorization.Action -eq "Microsoft.Authorization/roleAssignments/delete"}

foreach($roleAssignmentAction in $roleAssignmentActions){
 
  $assignmentName = $roleAssignmentAction.resourceId.split("/") | select -last 1
  $parsedAssignment = $roleAssignments | Where-Object {$_.RoleAssignmentName -eq $assignmentName}

  $assignmentLocation = $roleAssignmentAction.properties.hierarchy.split("/") | select -last 1
  if($subscriptions.id -like $assignmentLocation){

    $assignmentLocation = $subscriptions | where-object {$_.id -like $assignmentLocation} | select name
    $assignmentLocation = $assignmentLocation.name

  }

  if($roleAssignmentAction.authorization.action -eq "Microsoft.Authorization/roleAssignments/delete") {
  
    $roleAssigned = $roleAssignmentAction.properties.responsebody | convertfrom-json
    $resourceScope = $roleassigned.properties.scope
    $roleDefinitionID = $roleAssigned.Properties.roledefinitionid.split("/") | select -last 1
    $roleAssignmentName = $roleDefinitions | Where-Object {$_.id -eq $roleDefinitionID } | select name
    $roleAssignmentName = $roleAssignmentName.name

  }else{
    $roleAssignmentName = ($roleAssignments | Where-Object {$_.RoleAssignmentName -eq $assignmentName} | select RoleDefinitionName).RoleDefinitionName
  }

    $time = ([DateTime]$roleAssignmentAction.SubmissionTimeStamp).ToLocalTime()
    $formattedTime = Get-date -date $time -format G

    #Role assignments that have been deleted have no record of the displayname or signin name, so it will be left blank
    $emailOutput.Add([PSCustomObject]@{
      'Assignment Location' = $assignmentLocation
      #'Resource Scope' = $roleAssignmentAction.authorization.scope
      'Action' = $roleAssignmentAction.Authorization.Action.split("/") | select -last 1
      'Role Assigned' = $roleAssignmentName
      'Assigned To' = $parsedassignment.DisplayName
      'SignInName' = $parsedassignment.SignInName
      'Modified By' = $roleAssignmentAction.caller
      'Assignment Time' = $formattedTime
    })
}

#Create a count for the report and convert the data to html
$araCount = $emailOutput.count
$emailOutput = $emailOutput | convertto-html


# generate the style / body of the email
$emailBody = new-emailStyle_Body
$emailFrom = ""
$emailTo = ""
#$emailTo = ""

#If report catches a role assigment being created, send an email, else do nothing.
if ($araCount -ge 1) {`
  $Parameters = @{
      From        = $emailFrom
      To          = $emailTo
      Subject     = "$araCount Azure Role Assignments Created in last 24hrs"
      Body        = $emailBody
      BodyAsHTML  = $True
      Priority    = "Normal"
      SmtpServer  = ""
  }
}

# Send the email to ECS
Send-MailMessage @Parameters

