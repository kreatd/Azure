<#############################################################################
 
    Azure Automation Runbook 
    AUTHORS:  Dan Kreatsoulas
    CONTRIBUTORS:
    DATE:  12/19/2022
    COMMENT: This script will generate a list of role assignments that have been created within the past 24 hours.
    VERSION HISTORY:
    1.0 - 12/19/2022 - Created
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
      [enter team name]

  </body>
  </html>
"@
  return $Output
}

$emailOutput= [System.Collections.ArrayList]::new()
$subs = get-azsubscription

foreach($sub in $subs) {

#Set context, gather all roleassignments within the context and get all azactivity log entries that pertain to roleassignments/*
Set-AzContext $sub
$listofRoleAssignments = get-azroleassignment
$loggedAssignments = Get-AzLog -StartTime (Get-Date).AddDays(-1) | Where-Object {$_.Authorization.Action -like 'Microsoft.Authorization/roleAssignments/*' -and $_.OperationName -ne "Delete role assignment"}

#Only pull in assignments that have a status of "Started."  This corrects the bug where there's a % chance that the activity log is missing the succeeded status.
$loggedAssignments = $loggedAssignments | where {$_.status -eq "Succeeded"}

  foreach($assignment in $loggedAssignments) {
  #Loop through each assignment within the logged assignments and gather the necessary info for the report
  $assignment
  $assignmentName = $assignment.authorization.scope.split("/") | select -last 1
  $time = ([DateTime]$assignment.SubmissionTimeStamp).ToLocalTime()
  $formattedTime = Get-date -date $time -format G
  $parsedassignment = $listofRoleAssignments | where {$_.RoleAssignmentName -eq $assignmentName}
  $parsedassignment

  #If the scope's parent is the subscription, clip it out to remove irrelevant data from the report.
 <#   if($parsedassignment.scope -match "resourceGroups") {
        $scope = $parsedassignment.scope.split("resourceGroups/")
        $scope = $scope[1]
    }else{
        $scope = $parsedassignment.scope
    }
#>
  #Append report data to the output of the report.
  #Ignore null data (this happens when you create and delete the same role assignment within the window of this report.)
if($null -ne $parsedassignment.scope -and $null -ne $parsedassignment.RoleDefinitionName -and $null -ne $parsedassignment.DisplayName)
  {
    [void]$emailOutput.Add([PSCustomObject]@{
        'Subscription' = $sub.name
        'Resource Scope' = $parsedassignment.scope
        'Role Assigned' = $parsedassignment.RoleDefinitionName
        'Assigned To' = $parsedassignment.DisplayName
        'Assigned By' = $assignment.caller
        'Assignment Time' = $formattedTime
    })
    }
  }  #}
}
#Create a count for the report and convert the data to html
$araCount = $emailOutput.count
$emailOutput = $emailOutput | convertto-html


# generate the style / body of the email
$emailBody = new-emailStyle_Body
$emailFrom = "[enter email]"
$emailTo = "[enter email]"

#If report catches a role assigment being created, send an email, else do nothing.
if ($araCount -ge 1) {`
  $Parameters = @{
      From        = $emailFrom
      To          = $emailTo
      Subject     = "$araCount Azure Role Assignments Created in last 24hrs"
      Body        = $emailBody
      BodyAsHTML  = $True
      Priority    = "Normal"
      SmtpServer  = "[smtpserver]"
  }
}

# Send the email
Send-MailMessage @Parameters

