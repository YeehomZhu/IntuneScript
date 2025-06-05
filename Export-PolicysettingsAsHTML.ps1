# This script retrieves device policies from Microsoft Graph and exports them to an HTML file.
# It requires the Microsoft.Graph.Devicemanagement module to be installed and connected to Microsoft Graph.
# Ensure you have the necessary permissions to access device management data in Microsoft Graph.
# Requires -Version 5.1                                                                                                                                                                                                                                     

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
`
`
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

    $allResults = @()
    $skip = 0
    $top = 50
    do {
        $json =  @{
            select = @(
                "SettingName"
                "SettingStatus"
                "ErrorCode"
                "SettingId"
                "SettingInstanceId"
            )
            skip   = $skip
            top    = $top
            filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
            orderBy = @()           
        } | ConvertTo-Json
        try {
            $deviceInfo = Invoke-MgGraphRequest `
                -Uri "beta/deviceManagement/reports/getConfigurationSettingsReport" `
                -Method POST `
                -Body $json

            $jsonResult = $deviceInfo | ConvertFrom-Json
            if ($null -ne $jsonResult.values) {
                $allResults += $jsonResult.values
            }
            $count = if ($null -ne $jsonResult.values) { $jsonResult.values.Count } else { 0 }
            $skip += $top
        }
        catch {
            Write-Error "Failed to retrieve configuration policies report: $_"
            break
        }
    } while ($count -eq $top)

    # Return as a similar object as original for compatibility
    return @{ values = $allResults }
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

# Helper function to get colored HTML for policy/setting status
function Get-StatusHtml {
    param(
        [string]$Status
    )
    switch ($Status) {
        "Compliant"      { return "<span style='color: #228B22; font-weight: bold;'>$Status</span>" }
        "Remediated"     { return "<span style='color: #228B22; font-weight: bold;'>$Status</span>" }
        "Noncompliant"   { return "<span style='color: #d73a49; font-weight: bold;'>$Status</span>" }
        "Error"          { return "<span style='color: #d73a49; font-weight: bold;'>$Status</span>" }
        "Conflict"       { return "<span style='color: #e36209; font-weight: bold;'>$Status</span>" }
        "Not applicable" { return "<span style='color: #6a737d;'>$Status</span>" }
        "Unknown"        { return "<span style='color: #6a737d;'>$Status</span>" }
        "InProgress"     { return "<span style='color: #005a9e;'>$Status</span>" }
        default          { return "<span>$Status</span>" }
    }
}

#######################################################################
#main script starts here
#Ensure the script is run with the necessary permissions   

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

# Collect all policy and setting info for HTML export
$allPolicyHtmlBlocks = @()

# Loop through each configuration policies and retrieve settings
foreach ($policy in $PolicyConfigurationresults) {
    $policyId = $policy.PolicyID
    $userId = $policy.UserID
    $PolicyBaseTypeName = $policy.PolicyBaseTypeName
    $settings = @()
    # Get settings for this policy
    switch ($PolicyBaseTypeName) {
        "Microsoft.Management.Services.Api.DeviceConfiguration" {
            $perPolicySettingResults = Get-ApiDeviceConfiguration -policyId $policyId -deviceId $DeviceId -userId $userId
            $settings = $perPolicySettingResults.values | ForEach-Object {
                Export-policySettingDetail -PolicySettings $_
            }
        }
        "Microsoft.Management.Services.Api.DeviceManagementIntent"{
               $perPolicySettingResults = Get-ApiDeviceConfiguration -policyId $policyId -deviceId $DeviceId -userId $userId
                $settings = $perPolicySettingResults.values | ForEach-Object {
                Export-policySettingDetail -PolicySettings $_
            }
        }
        "DeviceManagementConfigurationPolicy" {
            $perPolicySettingResults = Get-DeviceManagementConfigurationPolicy -policyId $policyId -deviceId $DeviceId -userId $userId 
            $settings = $perPolicySettingResults.values | ForEach-Object {
                Export-DeviceManagementConfigurationPolicySettingDetail -PolicySettings $_
            }
        }
        "DeviceConfigurationAdmxPolicy" {
            $perPolicySettingResults = Get-DeviceConfigurationAdmxPolicy -policyId $policyId -deviceId $DeviceId -userId $userId
            $settings = $perPolicySettingResults.values | ForEach-Object {
                Export-policySettingDetail -PolicySettings $_
            }
        }
        default {
            $settings = @()
        }
    }

    # Build HTML for settings table
    if ($null -ne $settings) {
        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine("<table border='1' style='border-collapse:collapse;'>") | Out-Null
        $sb.AppendLine("<tr>") | Out-Null
        $settings[0].psobject.Properties.Name | ForEach-Object { $sb.AppendLine("<th>$_</th>") | Out-Null }
        $sb.AppendLine("</tr>") | Out-Null
        foreach ($row in $settings) {
            $sb.AppendLine("<tr>") | Out-Null
            foreach ($prop in $row.psobject.Properties) {
                $value = $prop.Value
                if ($prop.Name -match "SettingStatus") {
                    $value = Get-StatusHtml $value
                } elseif ($null -eq $value) {
                    $value = ""
                }
                $sb.AppendLine("<td>$value</td>") | Out-Null
            }
            $sb.AppendLine("</tr>") | Out-Null
        }
        $sb.AppendLine("</table>") | Out-Null
        $settingsTable = $sb.ToString()
    } else {
        $settingsTable = "<i>No settings found for this policy.</i>"
    }

    # Build HTML for this policy (collapsible)
    $policyBlock = @"
<details>
  <summary>
    <b>Policy Name:</b> $($policy.PolicyName) &nbsp; 
    <b>Status:</b> $(Get-StatusHtml $policy.Stats) &nbsp; 
    <b>Type:</b> $($policy.PolicyBaseTypeName) &nbsp; 
    <b>Policy ID:</b> $($policy.PolicyID) &nbsp; 
    <b>User:</b> $($policy.LoggedUser) &nbsp; 
    <b>Policy Type:</b> $($policy.PolicyType)
  </summary>
  <div>
    <b>Settings:</b><br>
    $settingsTable
  </div>
</details>
"@

    # Add the policy block to the collection
    $allPolicyHtmlBlocks += $policyBlock
}

# Compose the full HTML document with a dynamic, unconstrained layout
$htmlHeader = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset='UTF-8'>
    <title>Device Policies Report</title>
    <link href="https://fonts.googleapis.com/css?family=Segoe+UI:400,700&display=swap" rel="stylesheet">
    <style>
        body { 
            font-family: 'Segoe UI', Arial, sans-serif; 
            margin: 0; 
            background: #f6f8fa; 
            color: #222; 
        }
        .container {
            margin: 30px auto 30px auto;
            background: #fff;
            border-radius: 10px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.08);
            padding: 32px 36px 36px 36px;
            width: auto;
        }
        h1 {
            text-align: center;
            color: #2d6cdf;
            margin-bottom: 32px;
            letter-spacing: 1px;
        }
        details {
            margin-bottom: 1.5em;
            border: 1px solid #e1e4e8;
            border-radius: 7px;
            background: #fafdff;
            box-shadow: 0 1px 4px rgba(44, 62, 80, 0.04);
            transition: box-shadow 0.2s;
        }
        details[open] {
            box-shadow: 0 2px 8px rgba(44, 62, 80, 0.10);
        }
        summary {
            font-size: 1.13em;
            font-weight: 600;
            cursor: pointer;
            padding: 12px 18px;
            background: #eaf1fb;
            border-radius: 7px 7px 0 0;
            outline: none;
        }
        .policy-info {
            padding: 18px 24px 12px 24px;
        }
        table {
            margin-top: 0.5em;
            border-collapse: collapse;
            width: auto;
            min-width: 300px;
            background: #fff;
            border-radius: 6px;
            overflow: auto;
            box-shadow: 0 1px 4px rgba(44, 62, 80, 0.03);
        }
        th, td {
            padding: 7px 12px;
            text-align: left;
            white-space: pre-line;
        }
        th {
            background: #eaf1fb;
            color: #2d6cdf;
            font-weight: 600;
            border-bottom: 2px solid #d1e3fa;
        }
        tr:nth-child(even) td {
            background: #f5f8fc;
        }
        tr:hover td {
            background: #e6f0fa;
        }
        .no-settings {
            color: #888;
            font-style: italic;
            margin: 8px 0 8px 0;
        }
        @media (max-width: 700px) {
            .container { padding: 10px; }
            table, th, td { font-size: 0.98em; }
            summary { font-size: 1em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Device Policies Report</h1>
        <h2 style="color:#2d6cdf; font-size:1.2em; margin-top:0;">Device ID: $DeviceId</h2>
        <p style="color:#555; margin-bottom:24px;">This report lists all configuration policies and their settings for the specified device.</p>
"@

# Footer for the HTML document
$htmlFooter = @"
    </div>
</body>
</html>
"@

# Write to HTML file,
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$exportPath = "C:\temp\DevicePoliciesReport_$timestamp.html"

# Combine header, policy blocks, and footer into the final HTML content
$htmlContent = $htmlHeader + ($allPolicyHtmlBlocks -join "`n") + $htmlFooter

# Export the HTML content to the specified file
$htmlContent | Set-Content -Path $exportPath -Encoding UTF8

#open html file in default browser
Start-Process $exportPath

Write-Host "HTML report created at $exportPath"

# Disconnect from Microsoft Graph
Disconnect-MgGraph

