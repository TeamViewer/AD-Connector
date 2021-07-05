# Copyright (c) 2018-2021 TeamViewer Germany GmbH
# See file LICENSE

$tvApiVersion = "v1"
$tvApiBaseUrl = "https://webapi.teamviewer.com"

function ConvertTo-TeamViewerRestError {
    param([parameter(ValueFromPipeline)]$err)
    Process {
        try { return ($err | Out-String | ConvertFrom-Json) }
        catch { return $err }
    }
}

function Invoke-TeamViewerRestMethod {
    # TeamViewer Web API requires TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $method = (& { param($Method) $Method } @args)
    if ($method -in "Put", "Delete") {
        # There is a known issue for PUT and DELETE operations to hang on Windows Server 2012.
        # Use `Invoke-WebRequest` for those type of methods. (see issue ERD-519)
        try { return ((Invoke-WebRequest -UseBasicParsing @args).Content | ConvertFrom-Json) }
        catch [System.Net.WebException] {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.BaseStream.Position = 0
            Throw ($reader.ReadToEnd() | ConvertTo-TeamViewerRestError)
        }
    }
    else {
        try { return Invoke-RestMethod -ErrorVariable restError @args }
        catch { Throw ($restError | ConvertTo-TeamViewerRestError) }
    }
}

function Invoke-TeamViewerPing($accessToken) {
    $result = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/ping" -Method Get -Headers @{authorization = "Bearer $accessToken" }
    return $result.token_valid
}

function Get-TeamViewerUser($accessToken) {
    $result = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Get -Headers @{authorization = "Bearer $accessToken" } `
        -Body @{full_list = $true }
    $userDict = @{ }
    ($result.users | ForEach-Object { $userDict[$_.email] = $_ })
    return $userDict
}

function Add-TeamViewerUser($accessToken, $user) {
    $missingFields = (@('name', 'email', 'language') | Where-Object { !$user[$_] })
    if ($missingFields.Count -gt 0) {
        Throw "Cannot create user! Missing required fields [$missingFields]!"
    }
    $payload = @{ }
    @('email', 'password', 'permissions', 'name', 'language', 'sso_customer_id') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Post -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Edit-TeamViewerUser($accessToken, $userId, $user) {
    $payload = @{ }
    @('email', 'name', 'permissions', 'password', 'active') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Disable-TeamViewerUser($accessToken, $userId) {
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes((@{active = $false } | ConvertTo-Json)))
}

function Get-TeamViewerAccount($accessToken, [switch] $NoThrow = $false) {
    try { return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/account" -Method Get -Headers @{authorization = "Bearer $accessToken" } }
    catch { if (!$NoThrow) { Throw } }
}

function Get-TeamViewerConditionalAccessGroup($accessToken) {
    $continuationToken = $null;
    Do {
        $payload = @{ }
        if ($continuationToken) {
            $payload.continuation_token = $continuationToken
        }
        $response = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/conditionalaccess/directorygroups" `
            -Method Get -Headers @{authorization = "Bearer $accessToken" } -Body $payload
        Write-Output $response.directory_groups
        $continuationToken = $response.continuation_token
    } While ($continuationToken)
}

function Add-TeamViewerConditionalAccessGroup($accessToken, $groupName) {
    $payload = @{ name = $groupName }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/conditionalaccess/directorygroups" `
        -Method Post -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Get-TeamViewerConditionalAccessGroupUser($accessToken, $groupID) {
    $continuationToken = $null
    Do {
        $payload = @{ }
        if ($continuationToken) {
            $payload.continuation_token = $continuationToken
        }
        $response = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/conditionalaccess/directorygroups/$groupID/users" `
            -Method Get -Headers @{authorization = "Bearer $accessToken" } -Body $payload
        Write-Output $response.directory_group.user_ids
        $continuationToken = $response.continuation_token
    } While ($continuationToken)
}

function Add-TeamViewerConditionalAccessGroupUser($accessToken, $groupID, $userIDs) {
    $payload = @{
        member_type = 'User';
        members     = @($userIDs);
    }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/conditionalaccess/directorygroups/$groupID" `
        -Method Post -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Remove-TeamViewerConditionalAccessGroupUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
    param($accessToken, $groupID, $userIDs)
    $payload = @{
        member_type = 'User';
        members     = @($userIDs);
    }
    if ($PSCmdlet.ShouldProcess($userIDs)) {
        return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/conditionalaccess/directorygroups/$groupID/members" `
            -Method Delete -Headers @{authorization = "Bearer $accessToken" } `
            -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
    }
}

function Get-TeamViewerUserGroup($accessToken) {
    $paginationToken = $null
    do {
        $payload = @{}
        if ($paginationToken) {
            $payload.paginationToken = $paginationToken
        }
        $response = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/usergroups" `
            -Method Get -Headers @{authorization = "Bearer $accessToken" } -Body $payload
        Write-Output $response.resources
        $paginationToken = $response.nextPaginationToken
    } while ($paginationToken)
}

function Add-TeamViewerUserGroup($accessToken, $groupName) {
    $payload = @{ name = $groupName }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/usergroups" `
        -Method Post -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Get-TeamViewerUserGroupMember($accessToken, $groupID) {
    $paginationToken = $null
    do {
        $payload = @{}
        if ($paginationToken) {
            $payload.paginationToken = $paginationToken
        }
        $response = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/usergroups/$groupID/members" `
            -Method Get -Headers @{authorization = "Bearer $accessToken" } -Body $payload
        Write-Output $response.resources
        $paginationToken = $response.nextPaginationToken
    } while ($paginationToken)
}

function Add-TeamViewerUserGroupMember($accessToken, $groupID, $accountIDs) {
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/usergroups/$groupID/members" `
        -Method Post -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($accountIDs))))
}

function Remove-TeamViewerUserGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
    param($accessToken, $groupID, $accountIDs)
    if ($PSCmdlet.ShouldProcess($accountIDs)) {
        return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/usergroups/$groupID/members" `
            -Method Delete -Headers @{authorization = "Bearer $accessToken" } `
            -ContentType "application/json; charset=utf-8" `
            -Body ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($accountIDs))))
    }
}
