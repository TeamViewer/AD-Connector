# Copyright (c) 2018 TeamViewer GmbH
# See file LICENSE

$tvApiVersion = "v1"
$tvApiBaseUrl = "https://webapi.teamviewer.com"

function ConvertTo-TeamViewerRestError {
    param([parameter(ValueFromPipeline)]$err)
    try { return ($err | Out-String | ConvertFrom-Json) }
    catch { return $err }
}

function Invoke-TeamViewerRestMethod {
    $method = (& {param($Method) $Method} @args)
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
    $result = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/ping" -Method Get -Headers @{authorization = "Bearer $accessToken"}
    return $result.token_valid
}

function Get-TeamViewerUser($accessToken) {
    $result = Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Get -Headers @{authorization = "Bearer $accessToken"} `
        -Body @{full_list = $true}
    $userDict = @{}
    ($result.users | ForEach-Object { $userDict[$_.email] = $_ })
    return $userDict
}

function Add-TeamViewerUser($accessToken, $user) {
    $missingFields = (@('name', 'email', 'language') | Where-Object { !$user[$_] })
    if ($missingFields.Count -gt 0) {
        Throw "Cannot create user! Missing required fields [$missingFields]!"
    }
    $payload = @{}
    @('email', 'password', 'permissions', 'name', 'language', 'sso_customer_id') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Post -Headers @{authorization = "Bearer $accessToken"} `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Edit-TeamViewerUser($accessToken, $userId, $user) {
    $payload = @{}
    @('email', 'name', 'permissions', 'password', 'active') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken"} `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Disable-TeamViewerUser($accessToken, $userId) {
    return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken"} `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes((@{active = $false} | ConvertTo-Json)))
}

function Get-TeamViewerAccount($accessToken, [switch] $NoThrow = $false) {
    try { return Invoke-TeamViewerRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/account" -Method Get -Headers @{authorization = "Bearer $accessToken"} }
    catch { if (!$NoThrow) { Throw } }
}