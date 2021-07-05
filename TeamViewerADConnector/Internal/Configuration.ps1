# Copyright (c) 2018-2021 TeamViewer Germany GmbH
# See file LICENSE

function Import-Configuration($filename) {
    $defaultConfiguration = @{
        ApiToken                    = ''
        ActiveDirectoryRoot         = ''
        ActiveDirectoryGroups       = @()
        UserLanguage                = 'en'
        UseDefaultPassword          = $true
        DefaultPassword             = ''
        UseSsoCustomerId            = $false
        UseGeneratedPassword        = $false
        SsoCustomerId               = ''
        TestRun                     = $true
        DeactivateUsers             = $true
        RecursiveGroups             = $true
        UseSecondaryEmails          = $true
        EnableConditionalAccessSync = $false
        EnableUserGroupsSync        = $false
    }
    if (Test-Path $filename) {
        $configuration = (Get-Content $filename | Out-String | ConvertFrom-Json)
        $defaultConfiguration.Keys | `
            Where-Object { !$configuration.PSObject.Properties[$_] } | `
            ForEach-Object { $configuration | Add-Member $_ $defaultConfiguration[$_] }
    }
    else {
        $configuration = (New-Object PSObject -Prop $defaultConfiguration)
    }
    $configuration | Add-Member Filename $filename
    return $configuration
}

function Save-Configuration($config) {
    $excluded = @('Filename')
    $configuration | Select-Object -Property * -ExcludeProperty $excluded | `
        ConvertTo-Json | Set-Content -Encoding UTF8 -Path $configuration.Filename
}

function Confirm-Configuration($config) {
    if (!($config.UseDefaultPassword -xor $config.UseGeneratedPassword -xor $config.UseSsoCustomerId)) {
        Throw "One of the parameters 'UseDefaultPassword', 'UseSsoCustomerId' or 'UseGeneratedPassword' must be set in the configuration. "
    }
    if ($config.UseDefaultPassword -And [string]::IsNullOrWhiteSpace($config.DefaultPassword)) {
        Throw "The parameter 'DefaultPassword' cannot be empty if 'UseDefaultPassword' is configured."
    }
    if ($config.UseSsoCustomerId -And [string]::IsNullOrWhiteSpace($config.SsoCustomerId)) {
        Throw "The parameter 'SsoCustomerId' cannot be empty if 'UseSsoCustomerId' is configured."
    }
}
