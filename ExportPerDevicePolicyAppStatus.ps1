
function Read-HostYesNo ([string]$Title, [string]$Prompt, [boolean]$Default)
{
    # Set up native PowerShell choice prompt with Yes and No
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No"
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    
    # Set default option
    $defaultChoice = 0 # first choice = Yes
    if ($Default -eq $false) { # only if it was given and is false
        $defaultChoice = 1 # second choice = No
    }

    $result = $Host.UI.PromptForChoice($Title, $Prompt, $options, $defaultChoice)
    
    if ($result -eq 0) { # 0 is yes
        return $true
    } else {
        return $false
    }
}


#######################################################################


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

#######################################################################


function Get-devicepolicies()
{
  param
    (
        [Parameter(Mandatory=$true)]$deviceId
    )


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
            filter = "((PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceConfiguration') or (PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') or (PolicyBaseTypeName eq 'DeviceConfigurationAdmxPolicy') or (PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceManagementIntent')) and (IntuneDeviceId eq '$deviceID' )"
            skip = 0
            top = 50
            orderBy = @("PolicyName")} | ConvertTo-Json

        Write-Output $json


        $filePath = "C:\temp\policytempfile.txt"

   
        $deviceinfo = Invoke-MgGraphRequest `
            -Uri "beta/deviceManagement/reports/getConfigurationPoliciesReportForDevice" `
            -Method POST `
            -Body $json `
            -OutputFilePath $filePath 


         # Read the contents of the text file
        $text = Get-Content -Path $filePath -Raw

        # Convert the text to JSON
        $jsonResult = $text | ConvertFrom-Json

        # Access the converted JSON object
       return $jsonResult




}

####################################################

function Export-policyDetail(){

    
    [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory=$true)]$Policies
    )

    $policyInfo = @()

    foreach($policy in $Policies) {
                        $info = New-Object -TypeName psobject
                        $info | Add-Member -MemberType NoteProperty -Name PolicyID -Value $policy[2]
                        $info | Add-Member -MemberType NoteProperty -Name PolicyBaseTypeName -Value $policy[1]
                        $info | Add-Member -MemberType NoteProperty -Name PolicyNAme -Value $policy[3]
                        $info | Add-Member -MemberType NoteProperty -Name PolicyType -Value $policy[7]
                        $info | Add-Member -MemberType NoteProperty -Name LoggedUser -Value $policy[8]
                         $info | Add-Member -MemberType NoteProperty -Name UserID -Value $policy[9]

                      
                    <#
                    PolicyStatus
                    0= unknown
                    1= notApplicable
                    2= Compliant
                    3= Remediated
                    4= Noncompliant
                    5= Error
                    6= Conflict
                    7= InProgress
                    #>

                    switch ($policy[4]) {
                                        "1" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Not applicable"
                                        }
                                        "2" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Compliant" 
                                        }
                                        "3" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Remediated"
                                        }
                                        "4" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Noncompliant"
                                        }
                                        "5" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Error"
                                        }
                                        "6" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Conflict"
                                        }
                                        "7" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "InProgress"
                                        }
                                        "0" {
                                            $info | Add-Member -MemberType NoteProperty -Name Stats -Value "Unknown"
                                        }
                                        }

                # get policySettinDetails 

                    <#
                    $deviceId = $policy[0]
                    $policyId = $policy[2]
                    $userId = $policy[5]
                    #>

               #  $thispolicysetting = Get-PolicySettingsReport -policyId $policy[2] -userId $policy[9] -deviceId $policy[0] -PolicyBaseTypeName $policy[1]

                 #$info | Add-Member -MemberType NoteProperty -Name Subsettings -Value  $thispolicysetting

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



function Get-PolicySettingsReport()
{

  [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory=$true)]$policyId,$deviceId,$userId,$PolicyBaseTypeName
    )

    $json = @()

        $jsonforothers = @{
	        select = @(
		        "SettingName"
		        "SettingStatus"
		        "ErrorCode"
		        "SettingInstanceId"
		        "SettingInstancePath"
	        )
	        skip = 0
	        top = 50
	        filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
	        orderBy = @(
	        )
        }| ConvertTo-Json

        $jsonforConfigurationSettingsReport = @{
	select = @(
		"SettingName"
		"SettingStatus"
		"ErrorCode"
		"SettingId"
		"SettingInstanceId"
	)
	skip = 0
	top = 50
	filter = "(PolicyId eq '$policyId') and (DeviceId eq '$deviceId') and (UserId eq '$userId')"
	orderBy = @(
	)
}



              switch ($PolicyBaseTypeName) {
                "Microsoft.Management.Services.Api.DeviceConfiguration" {
                    $url = "beta/deviceManagement/reports/getConfigurationSettingNoncomplianceReport" 
                    $json =  $jsonforothers
                }
                "DeviceConfigurationAdmxPolicy" {
                   $url = "beta/deviceManagement/reports/getGroupPolicySettingsDeviceSettingsReport" 
                   $json =  $jsonforothers
                }
                "DeviceManagementConfigurationPolicy" {
                    $url = "beta/deviceManagement/reports/getConfigurationSettingsReport" 
                    $json = $jsonforConfigurationSettingsReport
                }
                }


    
      $filePath = "C:\temp\configurationtempfile.txt"

      
   
     $policySettings = Invoke-MgGraphRequest `
    -Uri $url `
    -Method POST `
    -Body $json `
    -OutputFilePath $filePath 


    $text = Get-Content -Path $filePath -Raw

    # Convert the text to JSON
    $policySettings = $text | ConvertFrom-Json


    return $policySettings


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


ConnectToGraph

Select-MgProfile -Name "beta"

$DeviceName = Read-Host -Prompt "Please type the device name to check policy deployment status"

$devices =   Get-MgDeviceManagementManagedDevice -Filter "devicename eq '$DeviceName'" | select id, deviceName,AzureAdDeviceId,userprincipalname

$deviceCount = 0 
foreach($device in $devices)
{


$deviceID = $device.id


$jsonResult = Get-devicepolicies -deviceId $deviceID


$PolicyConfigurationresults = Export-policyDetail -Policies $jsonResult.Values


$allPolicyInformationofdevice = @()

 #$thispolicysetting = Get-policySettings -policyId $policyId -userId $userId -deviceId $deviceId
 Foreach($configuration in $PolicyConfigurationresults)
 {
    
        $thispolicysetting =  Get-PolicySettingsReport -policyId $configuration.PolicyID -userId $configuration.UserID -deviceId $deviceID -PolicyBaseTypeName $configuration.PolicyBaseTypeName 
        
           $info = New-Object -TypeName psobject
           $info | Add-Member -MemberType NoteProperty -Name PolicyType -Value $configuration.PolicyType
           $info | Add-Member -MemberType NoteProperty -Name PolicyNAme -Value $configuration.PolicyNAme
           $info | Add-Member -MemberType NoteProperty -Name LoggedUser -Value $configuration.LoggedUser
           $info | Add-Member -MemberType NoteProperty -Name Status -Value $configuration.Stats
    
        $subsettinginfo = @()
        foreach ($setting in $thispolicysetting.Values)
        {

      
            if($configuration.PolicyBaseTypeName -eq "DeviceManagementConfigurationPolicy")
            {
               $Fomatpolicysettings = Export-DeviceManagementConfigurationPolicySettingDetail -PolicySettings $setting 
              
            }
            else
            {
               $Fomatpolicysettings =  Export-policySettingDetail -PolicySettings $setting 
              
            }
        
       # Write-host  $Fomatpolicysettings
       # Write-host "##############################################################################################################"

      
         
            $subsettinginfo += $Fomatpolicysettings
        }
            
            $subsettinginfo | Add-Member -MemberType NoteProperty -Name LoggedUser -Value $configuration.LoggedUser
            $subsettinginfo | Add-Member -MemberType NoteProperty -Name MainPolicyNameBelongs -Value $configuration.PolicyNAme

        #$subsettinginfoString =  ($subsettinginfo | Out-String).Trim()
            
       # $subsettinginfo | Add-Member -MemberType NoteProperty -Name SubsettingInfo -Value $subsettinginfoString
        
        $allPolicyInformationofdevice += $subsettinginfo
 }

  
$exportCSV = Read-HostYesNo -Prompt "Do you want to export all returned devices to a CSV?" -Default $true

if($exportCSV){
    $path = "c:\temp"
    $append = "_$(Get-Date -f m)"
    if(! (Test-Path -Path $path -PathType Container)){
        New-Item -Path $path -ItemType Directory
    }
     $allPolicyInformationofdevice  | Export-Csv -Path ("{0}\devicename{1}{2}{3}.csv" -f $path,$DeviceName, $append,$deviceCount)
    Write-Host ("CSV created at {0}\devicename{1}{2}{3}.csv containing device info..." -f $path,$DeviceName,$append,$deviceCount)
    Write-Host
}

$deviceCount += 1

}

remove-item "C:\temp\configurationtempfile.txt"
remove-item "C:\temp\policytempfile.txt"






