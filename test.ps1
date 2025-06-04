# This script retrieves device policies from Microsoft Graph and exports them to an HTML file.
# It requires the Microsoft.Graph.Devicemanagement module to be installed and connected to Microsoft Graph.
function ConnectToGraph
{
    if (Get-Module -ListAvailable -Name Microsoft.Graph.Devicemanagement) 
    {
    } 
    else {
        Write-Host "Microsoft.Graph.Devicemanagement  Module does not exist, installing..."
        Install-Module Microsoft.Graph -Scope CurrentUser
    }
  
    #Connect-MSGraph -PSCredential $creds
    
    
    Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All", " DeviceManagementConfiguration.ReadWrite.All"

}

####################################################
# Function to retrieve device policies
# This function retrieves policies for a specific device ID from Microsoft Graph.
function Get-DevicePolicies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DeviceId
    )

    $allResults = @()
    $skip = 0
    $top = 50

    do {
        $json = @{
            select = @(
                "IntuneDeviceId",
                "PolicyBaseTypeName",
                "PolicyId",
                "PolicyStatus",
                "UPN",
                "UserId",
                "PspdpuLastModifiedTimeUtc",
                "PolicyName",
                "UnifiedPolicyType"
            )
            filter = "((PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceConfiguration') or (PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') or (PolicyBaseTypeName eq 'DeviceConfigurationAdmxPolicy') or (PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceManagementIntent')) and (IntuneDeviceId eq '$DeviceId')"
            skip = $skip
            top = $top
            orderBy = @("PolicyName")
        } | ConvertTo-Json

        try {
            $deviceInfo = Invoke-MgGraphRequest `
                -Uri "beta/deviceManagement/reports/getConfigurationPoliciesReportForDevice" `
                -Method POST `
                -Body $json

            $jsonResult = $deviceInfo | ConvertFrom-Json

            $allResults += $jsonResult.Values
            $skip += $top
        }
        catch {
            Write-Error "Failed to retrieve device policies: $_"
            break
        }
    } while ($jsonResult.values.count -ge 50)

    return $allResults
}

####################################################

# Function to export policy details
# This function processes the policies and returns a structured object with relevant details.
# It includes policy ID, base type name, policy name, status, and user information.
# It also maps the policy status to a human-readable format.    


function Export-PolicyDetail {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Policies
    )

    $policyInfo = @()

    foreach ($policy in $Policies) {
        # Support both hashtable/object and array input
        if ($policy -is [hashtable] -or $policy -is [psobject]) {
            $policyId = $policy.PolicyId
            $baseType = $policy.PolicyBaseTypeName
            $policyName = $policy.PolicyName
            $policyType = $policy.UnifiedPolicyType
            $userId = $policy.UserId
            $upn = $policy.UPN
            $status = $policy.PolicyStatus
            $deviceId = $policy.IntuneDeviceId
        } else {
            # fallback for array input
            $deviceId = $policy[0]
            $baseType = $policy[1]
            $policyId = $policy[2]
            $status = $policy[4]
            $upn = $policy[8]
            $userId = $policy[9]
            $policyName = $policy[3]
            $policyType = $policy[7]
        }

        $info = [PSCustomObject]@{
            PolicyID            = $policyId
            PolicyBaseTypeName  = $baseType
            PolicyName          = $policyName
            PolicyType          = $policyType
            UserID              = $userId
            LoggedUser          = if ($userId -eq "00000000-0000-0000-0000-000000000000") { "SystemAccount" } else { $upn }
            Stats               = switch ($status) {
                "1" { "Not applicable" }
                "2" { "Compliant" }
                "3" { "Remediated" }
                "4" { "Noncompliant" }
                "5" { "Error" }
                "6" { "Conflict" }
                "7" { "InProgress" }
                "0" { "Unknown" }
                default { "Unknown" }
            }
        }

        $policyInfo += $info
    }

    return $policyInfo
}

####################################################

<#
            PolicyBaseTypeName.DeviceConfiguration,
            PolicyBaseTypeName.DeviceManagementConfigurationPolicy,
            PolicyBaseTypeName.DeviceConfigurationAdmxPolicy,
            PolicyBaseTypeName.DeviceIntent

            #>
        #all-in-one function to get policy settings report based on PolicyBaseTypeName
# This function retrieves policy settings report for a specific policy, device, and user.
function Get-PolicySettingsReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$policyId,
        [Parameter(Mandatory = $true)]
        [string]$deviceId,
        [Parameter(Mandatory = $true)]
        [string]$userId,
        [Parameter(Mandatory = $true)]
        [string]$PolicyBaseTypeName
    )

    # Validate input
    if (-not $policyId -or -not $deviceId -or -not $userId -or -not $PolicyBaseTypeName) {
        Write-Error "All parameters are required."
        return $null
    }

    # Define request bodies for different policy types
    $jsonForOthers = @{
        select = @(
            "SettingName"
            "SettingStatus"
            "ErrorCode"
            "SettingInstanceId"
            "SettingInstancePath"
        )
        skip   = 0
        top    = 50
        filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
        orderBy = @()
    } | ConvertTo-Json

    $jsonForConfigurationSettingsReport = @{
        select = @(
            "SettingName"
            "SettingStatus"
            "ErrorCode"
            "SettingId"
            "SettingInstanceId"
        )
        skip   = 0
        top    = 50
        filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
        orderBy = @()
    } | ConvertTo-Json

    # Determine endpoint and body
    switch ($PolicyBaseTypeName) {
        "Microsoft.Management.Services.Api.DeviceConfiguration" {
            $url = "beta/deviceManagement/reports/getConfigurationSettingNoncomplianceReport"
            $json = $jsonForOthers
        }
        "DeviceConfigurationAdmxPolicy" {
            $url = "beta/deviceManagement/reports/getGroupPolicySettingsDeviceSettingsReport"
            $json = $jsonForOthers
        }
        "DeviceManagementConfigurationPolicy" {
            $url = "beta/deviceManagement/reports/getConfigurationSettingsReport"
            $json = $jsonForConfigurationSettingsReport
        }
        default {
            Write-Error "Unsupported PolicyBaseTypeName: $PolicyBaseTypeName"
            return $null
        }
    }

    try {
        $response = Invoke-MgGraphRequest -Uri $url -Method POST -Body $json
        return  $response
    }
    catch {
        Write-Error "Failed to retrieve policy settings: $_"
        return $null
    }
}

#######################################################################
# Query PolicyBaseTypeName Microsoft.Management.Services.Api.DeviceConfiguration
# This function retrieves the configuration policies report for a specific device.
function Get-ApiDeviceConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$policyId,
        [Parameter(Mandatory = $true)]
        [string]$deviceId,
        [Parameter(Mandatory = $true)]
        [string]$userId
    )

    $json =  @{
        select = @(
            "SettingName"
            "SettingStatus"
            "ErrorCode"
            "SettingInstanceId"
            "SettingInstancePath"
        )
        skip   = 0
        top    = 50
        filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
        orderBy = @()
    } | ConvertTo-Json

    try {
        $deviceInfo = Invoke-MgGraphRequest `
            -Uri "beta/deviceManagement/reports/getConfigurationSettingNoncomplianceReport" `
            -Method POST `
            -Body $json

        return $deviceInfo
    }
    catch {
        Write-Error "Failed to retrieve configuration policies report: $_"
        return $null
    }
}
#######################################################################
#query PolicyBaseTypeName DeviceManagementConfigurationPolicy
function Get-DeviceManagementConfigurationPolicy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$policyId,
        [Parameter(Mandatory = $true)]
        [string]$deviceId,
        [Parameter(Mandatory = $true)]
        [string]$userId
    )

    $json =  @{
        select = @(
            "SettingName"
            "SettingStatus"
            "ErrorCode"
            "SettingId"
            "SettingInstanceId"
        )
        skip   = 0
        top    = 50
        filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
        orderBy = @()           

    } | ConvertTo-Json
    try {
        $deviceInfo = Invoke-MgGraphRequest `
            -Uri "beta/deviceManagement/reports/getConfigurationSettingsReport" `
            -Method POST `
            -Body $json

        return $deviceInfo
    }
    catch {
        Write-Error "Failed to retrieve configuration policies report: $_"
        return $null
    }
}
#######################################################################
#query PolicyBaseTypeName DeviceConfigurationAdmxPolicy
function Get-DeviceConfigurationAdmxPolicy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$policyId,
        [Parameter(Mandatory = $true)]
        [string]$deviceId,
        [Parameter(Mandatory = $true)]
        [string]$userId
    )

    $json =  @{
        select = @(
            "SettingName"
            "SettingStatus"
            "ErrorCode"
            "SettingInstanceId"
            "SettingInstancePath"
        )
        skip   = 0
        top    = 50
        filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
        orderBy = @()       
    } | ConvertTo-Json
    try {

        # the request returned non-json data, so we need to convert it to JSON  
        $outputFilePath = [System.IO.Path]::GetTempFileName()
        Invoke-MgGraphRequest `
            -Uri "beta/deviceManagement/reports/getGroupPolicySettingsDeviceSettingsReport" `
            -Method POST `
            -Body $json `
            -OutputFilePath $outputFilePath

        $jsonContent = Get-Content -Path $outputFilePath -Raw | ConvertFrom-Json
        Remove-Item $outputFilePath -ErrorAction SilentlyContinue
        # Convert the JSON content to a PowerShell object
     
        return  $jsonContent 
    }
    catch {
        Write-Error "Failed to retrieve configuration policies report: $_"
        return $null
    }   
}

#######################################################################
function Export-policySettingDetail(){


#This function use to modify output from getConfigurationPoliciesReportForDevice and format as policy status and result. 
    
    [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory=$true)]$PolicySettings
    )

                            <#
                                    "SettingName"
		                            "SettingStatus"
		                            "ErrorCode"
		                            "SettingInstanceId"
		                            "SettingInstancePath"
                            #>
                 $info = New-Object -TypeName psobject
                 $info | Add-Member -MemberType NoteProperty -Name SettingName -Value $PolicySettings[3]
                 $info | Add-Member -MemberType NoteProperty -Name SettingPath -Value $PolicySettings[2]


                 
                                        <#
                                        SettingStatus
              

                                        case 0: return Unknown;
                                        case 1: return NotApplicable;
                                        case 2: return Compliant;
                                        case 3: return Remediated;
                                        case 4: return NotCompliant;
                                        case 5: return Error;
                                        case 6: return Conflict;

                                        #>
                   switch ($PolicySettings[4]) {
                            "1" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Not applicable"
                            }
                            "2" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Compliant" 
                            }
                            "3" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Remediated"
                            }
                            "4" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Noncompliant"
                            }
                            "5" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Error"
                            }
                            "6" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Conflict"
                            }
                            "0" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Unknown"
                            }
                            }

        
                         return $info
   

}

#######################################################################
function Export-DeviceManagementConfigurationPolicySettingDetail(){
#This function use to modify output from getConfigurationPoliciesReportForDevice and format as policy status and result. 
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]$PolicySettings
    )
    
                            <#
                                    "SettingName"
		                            "SettingStatus"
		                            "ErrorCode"
		                            "SettingInstanceId"
		                            "SettingInstancePath"
                            #>
                 $info = New-Object -TypeName psobject
                  
                 $info | Add-Member -MemberType NoteProperty -Name SettingName -Value $PolicySettings[5]
              #   $info | Add-Member -MemberType NoteProperty -Name SettingPath -Value $PolicySettings[2]


                 
                                        <#
                                        SettingStatus
              

                                        case 0: return Unknown;
                                        case 1: return NotApplicable;
                                        case 2: return Compliant;
                                        case 3: return Remediated;
                                        case 4: return NotCompliant;
                                        case 5: return Error;
                                        case 6: return Conflict;

                                        #>
                   switch ($PolicySettings[4]) {
                            "1" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Not applicable"
                            }
                            "2" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Compliant" 
                            }
                            "3" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Remediated"
                            }
                            "4" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Noncompliant"
                            }
                            "5" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Error"
                            }
                            "6" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Conflict"
                            }
                            "0" {
                                $info | Add-Member -MemberType NoteProperty -Name SettingStatus -Value "Unknown"
                            }
                            }

        
                         return $info
   

}
#######################################################################
#main script starts here
# Ensure the script is run with the necessary permissions   

#connect to Microsoft Graph
ConnectToGraph

# Prompt for Device ID with input validation and optional parameter support
$DeviceId = Read-Host -Prompt "Please enter the Device ID to retrieve policies"
# Validate the Device ID input
if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    Write-Host "Device ID is required. Exiting script."
    exit
}

 $deviceAllpolices = Get-DevicePolicies -deviceId $DeviceId 

 # Check if any policies were retrieved
 if ($deviceAllpolices.Count -eq 0) {
    Write-Host "No policies found for the specified device ID."
    exit
 } else {
    $PolicyConfigurationresults = Export-policyDetail -Policies $deviceAllpolices
 }




# based on policy configuration results, query the policy settings report
foreach ($policy in $PolicyConfigurationresults) {
    $policyId = $policy.PolicyID
 
   # Write-Host $policyId
    
    $userId = $policy.UserID
    $PolicyBaseTypeName = $policy.PolicyBaseTypeName

  
    write-host "##################" 
    Write-Host $PolicyBaseTypeName
    write-host $policy.PolicyName

    #based on PolicyBaseTypeName, call the appropriate function to get policy settings
    switch ($PolicyBaseTypeName) {
        "Microsoft.Management.Services.Api.DeviceConfiguration" {

            
            $perPolicySettingResults = Get-ApiDeviceConfiguration -policyId $policyId -deviceId $DeviceId -userId $userId 
            # write-host $perPolicySettingResults.values

             foreach ($setting in $perPolicySettingResults.values) {
                $exportedSetting = Export-policySettingDetail -PolicySettings $setting
                write-host $exportedSetting.SettingName
                write-host $exportedSetting.SettingStatus
                write-host "------------------"
             }
                
        }
        "DeviceManagementConfigurationPolicy" {
          
            $perPolicySettingResults = Get-DeviceManagementConfigurationPolicy -policyId $policyId -deviceId $DeviceId -userId $userId | ConvertFrom-Json
             foreach ($setting in $perPolicySettingResults.values) {
                $exportedSetting = Export-DeviceManagementConfigurationPolicySettingDetail -PolicySettings $setting
                write-host $exportedSetting.SettingName
                write-host $exportedSetting.SettingStatus
                write-host "------------------"

             }
        }
        "DeviceConfigurationAdmxPolicy" {
             
            $perPolicySettingResults = Get-DeviceConfigurationAdmxPolicy -policyId $policyId -deviceId $DeviceId -userId $userId
         
             foreach ($setting in $perPolicySettingResults.values) {
                $exportedSetting = Export-policySettingDetail -PolicySettings $setting
                write-host $exportedSetting.SettingName
                write-host $exportedSetting.SettingStatus
                write-host "------------------"
             }
                
        }
        default {
            Write-Host "Unsupported PolicyBaseTypeName: $PolicyBaseTypeName"
            continue
        }
    }
    
    write-host "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 

  #  $perPolicySettingResults = Get-PolicySettingsReport -policyId $policyId -deviceId $DeviceId -userId $userId -PolicyBaseTypeName $PolicyBaseTypeName

    #normal device ConfigurationSettingNoncomplianceReport repert JSON format, need add .values 
   
    <#
    # Process the results based on PolicyBaseTypeName
    if ($PolicyBaseTypeName -eq "DeviceManagementConfigurationPolicy") {
        foreach ($setting in $perPolicySettingResults) {
            Export-DeviceManagementConfigurationPolicySettingDetail -PolicySettings $setting | Add-Member -InputObject $policy -MemberType NoteProperty -Name Settings -Value $_
        }
    } else {
        foreach ($setting in $perPolicySettingResults) {
            Export-policySettingDetail -PolicySettings $setting | Add-Member -InputObject $policy -MemberType NoteProperty -Name Settings -Value $_
        }

        #>
    
 }









<#
 #export results to html to c:temp
# Define the path for the HTML filter
$htmlFilePath = "DevicePolicies_$DeviceId.html"   

# Sort the results by PolicyBaseTypeName
$sortedResults = $PolicyConfigurationresults | Sort-Object PolicyBaseTypeName

# Color the output
$coloredResults = $sortedResults | ForEach-Object {
    $_.PolicyID = "<span style='color:blue;'>$($_.PolicyID)</span>"
    $_.PolicyBaseTypeName = "<span style='color:green;'>$($_.PolicyBaseTypeName)</span>"
    $_.PolicyName = "<span style='color:purple;'>$($_.PolicyName)</span>"
    $_.LoggedUser = "<span style='color:orange;'>$($_.LoggedUser)</span>"
    $_.Stats = "<span style='color:red;'>$($_.Stats)</span>"
    $_
}
# Convert the results to HTML format
$htmlContent = @"
<html>
<head>
    <title>Device Policies for Device ID: $DeviceId</title>
    <style>
        table { width: 100%; border-collapse: collapse; }
        th, td { border: 1px solid black; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Device Policies for Device ID: $DeviceId</h1>
    <table>
        <tr>
            <th>PolicyID</th>
            <th>PolicyBaseTypeName</th>
            <th>PolicyName</th>
            <th>PolicyType</th>
            <th>UserID</th>
            <th>LoggedUser</th>
            <th>Stats</th>
        </tr>
"@

foreach ($row in $coloredResults) {
    $htmlContent += "<tr>"
    $htmlContent += "<td>$($row.PolicyID)</td>"
    $htmlContent += "<td>$($row.PolicyBaseTypeName)</td>"
    $htmlContent += "<td>$($row.PolicyName)</td>"
    $htmlContent += "<td>$($row.PolicyType)</td>"
    $htmlContent += "<td>$($row.UserID)</td>"
    $htmlContent += "<td>$($row.LoggedUser)</td>"
    $htmlContent += "<td>$($row.Stats)</td>"
    $htmlContent += "</tr>"
}

$htmlContent += @"
    </table>
    <p>Generated on $(Get-Date)</p>
</body>
</html>
"@

# Save the HTML content to a file
$htmlContent | Out-File -FilePath $htmlFilePath -Encoding UTF8

# Open the HTML file in the default browser 
Start-Process $htmlFilePath
Write-Host "Device policies exported to $htmlFilePath"
# End of script
# Disconnect from Microsoft ConnectToGrap


#>