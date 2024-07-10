<# 
.DESCRIPTION 
  Get all assignments from an Intune device 
.INPUTS
 None required
.OUTPUTS
 Assignmments of an specific Intune Device
.NOTES
 Author: Jannik Reinhard (jannikreinhard.com)
 Modified by: Bartłomiej Tybura
 WORKS ONLY WITH AzureAD Module v. 2.0.2.140 (ADAL)
#> 
Param()

function Get-AuthToken {
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory)]
        $User
    )

    $userUpn = New-Object "System.Net.Mail.MailAddress" -ArgumentList $User
    $tenant = $userUpn.Host
    $AadModule = Get-Module -Name "AzureAD" -ListAvailable
    if ($AadModule -eq $null) {
        Write-Host "AzureAD PowerShell module not found, looking for AzureADPreview"
        $AadModule = Get-Module -Name "AzureADPreview" -ListAvailable
    }

    $adal = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    $adalforms = Join-Path $AadModule.ModuleBase "Microsoft.IdentityModel.Clients.ActiveDirectory.Platform.dll"

    Add-Type -Path $adal
    Add-Type -Path $adalforms
    # [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    # [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null
    $clientId = "" #the PowerShell Intune Graph app needs to be registered manually - see https://learn.microsoft.com/en-us/answers/questions/1659638/weve-detected-a-microsoft-intune-powershell-script
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob"
    $resourceAppIdURI = "https://graph.microsoft.com"
    $authority = "https://login.microsoftonline.com/$Tenant"

    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    $platformParameters = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" -ArgumentList "Auto"
    $userId = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserIdentifier" -ArgumentList ($User, "OptionalDisplayableId")
    $authResult = $authContext.AcquireTokenAsync($resourceAppIdURI,$clientId,$redirectUri,$platformParameters,$userId).Result

      
    $authHeader = @{
        'Content-Type'='application/json'
        'Authorization'="Bearer " + $authResult.AccessToken
        'ExpiresOn'=$authResult.ExpiresOn
        }

    return $authHeader
}

function Get-GraphCall {
    param(
        [Parameter(Mandatory)]
        $apiUri,
        [Parameter(Mandatory)]
        $method
    )
    return Invoke-RestMethod -Uri https://graph.microsoft.com/beta/$apiUri -Headers $authToken -Method $method
}

function Get-Device {
    param(
        [Parameter(Mandatory)]
        $deviceName
    )
    $result = Get-GraphCall -method GET -apiUri  ("deviceManagement/managedDevices?"+'$filter' + "=startswith(deviceName,'$deviceName')")
    return $result.value[0]
}


function Get-GroupMembership {
    param(
        [Parameter(Mandatory)]
        $deviceId
    )
    $groups = @()
    $deviceId = (Get-GraphCall -method GET -apiUri ("/devices?" + '$filter' + "=deviceId%20eq%20%27$deviceId%27")).value[0].id
    
    $result = Get-GraphCall -method GET -apiUri ("devices/$deviceId/memberOf")
    $result.value | ForEach-Object {$groups += " - $($_.displayName) ($($_.id))"}

    $result = Get-GraphCall -method GET -apiUri ("devices/$deviceId/transitiveMemberOf")
    $result.value | ForEach-Object {$groups += " - $($_.displayName) ($($_.id))"}
    
    ($groups | Sort-Object | Get-Unique) | ForEach-Object {Write-Host $_}
}

function Get-ConfigProfiles {
    param(
        [Parameter(Mandatory)]
        $deviceId
    )
    $body = @'
    {
        "select": [
            "PolicyName",
        ],
        "filter": "((PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceConfiguration') or (PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') or (PolicyBaseTypeName eq 'DeviceConfigurationAdmxPolicy') or (PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceManagementIntent')) and (IntuneDeviceId eq '
'@ + $deviceId + @'
')",
        "skip": 0,
        "top": 50,
        "orderBy": [
            "PolicyName"
        ]
    }
'@
    $result = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPoliciesReportForDevice" -Headers $authToken -Method POST -Body $body
    $profiles = @()
    $result.Values | ForEach-Object {$profiles += " - $($_[0])"
    }
    ($profiles | Sort-Object | Get-Unique) | ForEach-Object {Write-Host $_}
}

function Get-Applications {
    param(
        [Parameter(Mandatory)]
        $deviceId
    )
    $result = Get-GraphCall -method GET -apiUri ("/users('00000000-0000-0000-0000-000000000000')/mobileAppIntentAndStates('$deviceId')")
    $result.mobileAppList | ForEach-Object {
        Write-Host " - $($_.displayName)"
    }

}

function Get-DeviceInfo {
    param(
        [Parameter(Mandatory)]
        $device
    )

    Write-Host "  Hostname:                 $($device.deviceName)"
    Write-Host "  Deviceid:                 $($device.id)"
    Write-Host "  Ownertype:                $($device.ownerType)"
    Write-Host "  Enrollmenttime:           $($device.enrolledDateTime)"
    Write-Host "  OS version:               $($device.osVersion)"
    Write-Host "  User:                     $($device.emailAddress)"
    Write-Host "  EnrollmentProfile:        $($device.enrollmentProfileName)"
}

############################################ Start ######################################################

#Auth
if(-not $global:authToken){
    if($User -eq $null -or $User -eq ""){
    $User = Read-Host -Prompt "Please specify your user principal name for Azure Authentication"
    Write-Host
    }
    $global:authToken = Get-AuthToken -User $User -Verbose
}

# Get an device id
$deviceName = Read-Host "Enter the name of the device"
if($deviceName){
    $device = Get-Device -deviceName $deviceName
    if($device){
      $deviceId = $device.id
      Write-Host -ForegroundColor Yellow " ____________________________________"
      Write-Host -ForegroundColor Yellow "|        Getting Device Data         |"
      Write-Host -ForegroundColor Yellow "|____________________________________|"
      Write-Host
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Write-Host -ForegroundColor Yellow "|         Device summary         |"
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Get-DeviceInfo -device $device
      Write-Host
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Write-Host -ForegroundColor Yellow "|       Group memebership       |"
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Get-GroupMembership -deviceId $($device.azureActiveDirectoryDeviceId)
      Write-Host
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Write-Host -ForegroundColor Yellow "|        Config profiles        |"
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Get-ConfigProfiles -deviceId $deviceId
      Write-Host
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Write-Host -ForegroundColor Yellow "|          Applications         |"
      Write-Host -ForegroundColor Yellow "---------------------------------"
      Get-Applications -deviceId $deviceId
      Write-Host
    }else{
     Write-Host "Error corelated to device name. Plase try again." -ForegroundColor Red 
}else{
    Write-Host "Error, no device name provided. Run script again an provide proper name." -ForegroundColor Red
}
