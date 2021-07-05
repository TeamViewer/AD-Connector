# Copyright (c) 2018-2021 TeamViewer Germany GmbH
# See file LICENSE

BeforeAll {
    function Get-ActiveDirectoryGroupMember($root, $recursive, $path) { }
    function Select-ActiveDirectoryCommonName { }
    function Get-TeamViewerUser($accessToken) { }
    function Add-TeamViewerUser($accessToken, $user) { }
    function Edit-TeamViewerUser($accessToken, $userId, $user) { }
    function Disable-TeamViewerUser($accessToken, $userId) { }
    function Get-TeamViewerAccount($accessToken, [switch]$NoThrow) { }
    function Get-TeamViewerConditionalAccessGroup($accessToken) { }
    function Add-TeamViewerConditionalAccessGroup($accessToken, $groupName) { }
    function Get-TeamViewerConditionalAccessGroupUser($accessToken, $groupID) { }
    function Add-TeamViewerConditionalAccessGroupUser($accessToken, $groupID, $userIDs) { }
    function Remove-TeamViewerConditionalAccessGroupUser {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'accessToken', Justification = 'Needs to be mockable')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'groupID', Justification = 'Needs to be mockable')]
        param($accessToken, $groupID, $userIDs)
        if ($PSCmdlet.ShouldProcess($userIDs)) { }
    }

    function Get-TeamViewerUserGroup($accessToken) { }
    function Add-TeamViewerUserGroup($accessToken, $groupName) { }
    function Get-TeamViewerUserGroupMember($accessToken, $groupID) { }
    function Add-TeamViewerUserGroupMember($accessToken, $groupID, $accountIDs) { }
    function Remove-TeamViewerUserGroupMember {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'accessToken', Justification = 'Needs to be mockable')]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'groupID', Justification = 'Needs to be mockable')]
        param($accessToken, $groupID, $accountIDs)
        if ($PSCmdlet.ShouldProcess($accountIDs)) { }
    }

    . "$PSScriptRoot\..\..\..\TeamViewerADConnector\Internal\Sync.ps1"
}

Describe 'Invoke-SyncPrework' {
    BeforeAll {
        Mock Write-Synclog { }
    }

    It 'Should get all configured AD groups' {
        Mock Get-ActiveDirectoryGroupMember { }
        $configuration = @{ ActiveDirectoryGroups = @('Group1', 'Group2', 'Group3') }
        $syncContext = @{ }
        Invoke-SyncPrework $syncContext $configuration { }
        Assert-MockCalled Get-ActiveDirectoryGroupMember -Times 1 -Scope It `
            -ParameterFilter { $path -eq 'Group1' }
        Assert-MockCalled Get-ActiveDirectoryGroupMember -Times 1 -Scope It `
            -ParameterFilter { $path -eq 'Group2' }
        Assert-MockCalled Get-ActiveDirectoryGroupMember -Times 1 -Scope It `
            -ParameterFilter { $path -eq 'Group3' }
    }

    It 'Should get all TeamViewer company members' {
        Mock Get-TeamViewerUser { }
        $configuration = @{ ApiToken = 'TestApiToken' }
        $syncContext = @{ }
        Invoke-SyncPrework $syncContext $configuration { }
        Assert-MockCalled Get-TeamViewerUser -Times 1 -Scope It `
            -ParameterFilter { $accessToken -eq 'TestApiToken' }
    }

    It 'Should get all TeamViewer conditional access groups' {
        Mock Get-TeamViewerConditionalAccessGroup { }
        $configuration = @{ ApiToken = 'TestApiToken'; EnableConditionalAccessSync = $true }
        $syncContext = @{ }
        Invoke-SyncPrework $syncContext $configuration { }
        Assert-MockCalled Get-TeamViewerConditionalAccessGroup -Times 1 -Scope It `
            -ParameterFilter { $accessToken -eq 'TestApiToken' }
    }

    It 'Should get all TeamViewer conditional access group members' {
        Mock Get-TeamViewerConditionalAccessGroup {
            return @(
                [pscustomobject]@{ id = 'ca123'; name = 'TestGroup1' },
                [pscustomobject]@{ id = 'ca456'; name = 'TestGroup2' }
            )
        }
        Mock Get-TeamViewerConditionalAccessGroupUser { }
        $configuration = @{ ApiToken = 'TestApiToken'; EnableConditionalAccessSync = $true }
        $syncContext = @{ }
        Invoke-SyncPrework $syncContext $configuration { }
        Assert-MockCalled Get-TeamViewerConditionalAccessGroup -Times 1 -Scope It `
            -ParameterFilter { $accessToken -eq 'TestApiToken' }
        Assert-MockCalled Get-TeamViewerConditionalAccessGroupUser -Times 1 -Scope It `
            -ParameterFilter { $groupID -eq 'ca123' }
        Assert-MockCalled Get-TeamViewerConditionalAccessGroupUser -Times 1 -Scope It `
            -ParameterFilter { $groupID -eq 'ca456' }
    }

    It 'Should not handle TeamViewer conditional access groups if not configured' {
        Mock Get-TeamViewerConditionalAccessGroup { }
        $configuration = @{ ApiToken = 'TestApiToken'; EnableConditionalAccessSync = $false }
        $syncContext = @{ }
        Invoke-SyncPrework $syncContext $configuration { }
        Assert-MockCalled Get-TeamViewerConditionalAccessGroup -Times 0 -Scope It
    }

    Context 'Secondary Email Addresses' {
        It 'Should consider the secondary email of AD users if configured' {
            $testUserAd = @{
                Email           = 'user1@example.test'
                Name            = 'User 1'
                IsEnabled       = $true
                SecondaryEmails = @('user1_secondary@example.test')
            }
            Mock Get-ActiveDirectoryGroupMember { return @($testUserAd) }
            $configuration = @{ ActiveDirectoryGroups = @('Group1'); UseSecondaryEmails = $true }
            $syncContext = @{ }
            Invoke-SyncPrework $syncContext $configuration { }
            Assert-MockCalled Get-ActiveDirectoryGroupMember -Times 1 -Scope It `
                -ParameterFilter { $path -eq 'Group1' }
            $syncContext.UsersActiveDirectoryByEmail | Should -Not -BeNull
            $syncContext.UsersActiveDirectoryByEmail.Keys | Should -Contain 'user1@example.test'
            $syncContext.UsersActiveDirectoryByEmail.Keys | Should -Contain 'user1_secondary@example.test'
        }
    }
}

Describe 'Invoke-SyncUser' {
    BeforeAll {
        Mock Write-Synclog { }
    }

    It 'Should create TeamViewer users from AD groups members' {
        Mock Add-TeamViewerUser { }
        $configuration = @{ ActiveDirectoryGroups = @('Group1') }
        $syncContext = @{
            UsersActiveDirectory   = @(
                @{ Email = 'user1@example.test'; Name = 'Test User 1'; IsEnabled = $true },
                @{ Email = 'user2@example.test'; Name = 'Test User 2'; IsEnabled = $true }
            )
            UsersTeamViewerByEmail = @{
                'user1@example.test' = @{ email = 'user1@example.test'; name = 'Test User 1'; active = $true }
            }
        }
        Invoke-SyncUser $syncContext $configuration { }
        Assert-MockCalled Add-TeamViewerUser -Times 1 -Scope It `
            -ParameterFilter { $user -And $user.email -eq 'user2@example.test' }
    }

    It 'Should update existing TeamViewer users from AD groups members' {
        Mock Edit-TeamViewerUser { }
        $syncContext = @{
            UsersActiveDirectory   = @(
                @{ Email = 'user1@example.test'; Name = 'New Name'; IsEnabled = $true }
            )
            UsersTeamViewerByEmail = @{
                'user1@example.test' = @{ id = '123'; email = 'user1@example.test'; name = 'Old Name'; active = $true }
            }
        }
        $configuration = @{ ActiveDirectoryGroups = @('Group1') }
        Invoke-SyncUser $syncContext $configuration { }
        Assert-MockCalled Edit-TeamViewerUser -Times 1 -Scope It `
            -ParameterFilter { $user -And $user.Name -eq 'New Name' -And $userId -eq 123 }
    }

    It 'Should deactivate unknown TeamViewer users' {
        Mock Disable-TeamViewerUser { }
        $syncContext = @{
            UsersActiveDirectory        = @(
                @{ Email = 'user2@example.test'; Name = 'User 2'; IsEnabled = $true }
            )
            UsersActiveDirectoryByEmail = @{
                'user2@example.test' = @{ Email = 'user2@example.test'; Name = 'User 2'; IsEnabled = $true }
            }
            UsersTeamViewerByEmail      = @{
                'user1@example.test' = @{ id = '123'; email = 'user1@example.test'; name = 'User 1'; active = $true }
                'user2@example.test' = @{ id = '456'; email = 'user2@example.test'; name = 'User 2'; active = $true }
            }
        }
        $configuration = @{ ActiveDirectoryGroups = @('Group1'); DeactivateUsers = $true }
        Invoke-SyncUser $syncContext $configuration { }
        Assert-MockCalled Disable-TeamViewerUser -Times 1 -ParameterFilter { $userId -eq 123 }
    }

    It 'Should not deactivate the token account' {
        Mock Get-TeamViewerAccount {
            return @{ userid = '123'; email = 'user1@example.test'; name = 'User 1' }
        }
        Mock Disable-TeamViewerUser { }
        $syncContext = @{
            UsersActiveDirectory        = @()
            UsersActiveDirectoryByEmail = @{ }
            UsersTeamViewerByEmail      = @{
                'user1@example.test' = @{ id = '123'; email = 'user1@example.test'; name = 'User 1'; active = $true }
            }
        }
        $configuration = @{ ActiveDirectoryGroups = @('Group1'); DeactivateUsers = $true }
        Invoke-SyncUser $syncContext $configuration { }
        Assert-MockCalled Get-TeamViewerAccount -Times 1 -Scope It
        Assert-MockCalled Disable-TeamViewerUser -Times 0 -Scope It
    }

    Context 'Account Types' {
        BeforeAll {
            Mock Add-TeamViewerUser { }
        }

        It 'Should create TeamViewer users with predefined password' {
            $configuration = @{
                UseDefaultPassword    = $true
                DefaultPassword       = 'testpassword'
                ActiveDirectoryGroups = @('Group1')
            }
            $syncContext = @{
                UsersActiveDirectory   = @(@{ Email = 'user1@example.test'; Name = 'Test User 1'; IsEnabled = $true })
                UsersTeamViewerByEmail = @{ }
            }
            Invoke-SyncUser $syncContext $configuration { }
            Assert-MockCalled Add-TeamViewerUser -Times 1 -Scope It `
                -ParameterFilter { $user -And $user.password -eq 'testpassword' }
            $syncContext.UsersTeamViewerByEmail['user1@example.test'] | Should -Not -BeNullOrEmpty
        }

        It 'Should create TeamViewer users with generated password' {
            $configuration = @{
                UseGeneratedPassword  = $true
                ActiveDirectoryGroups = @('Group1')
            }
            $syncContext = @{
                UsersActiveDirectory   = @(@{ Email = 'user1@example.test'; Name = 'Test User 1'; IsEnabled = $true })
                UsersTeamViewerByEmail = @{ }
            }
            Invoke-SyncUser $syncContext $configuration { }
            Assert-MockCalled Add-TeamViewerUser -Times 1 -Scope It `
                -ParameterFilter { $user -And $user.password -eq '' }
            $syncContext.UsersTeamViewerByEmail['user1@example.test'] | Should -Not -BeNullOrEmpty
        }

        It 'Should create TeamViewer users that use Single Sign-On' {
            $configuration = @{
                UseSsoCustomerId      = $true
                SsoCustomerId         = 'testcustomeridentifier'
                ActiveDirectoryGroups = @('Group1')
            }
            $syncContext = @{
                UsersActiveDirectory   = @(@{ Email = 'user1@example.test'; Name = 'Test User 1'; IsEnabled = $true })
                UsersTeamViewerByEmail = @{ }
            }
            Invoke-SyncUser $syncContext $configuration { }
            Assert-MockCalled Add-TeamViewerUser -Times 1 -Scope It `
                -ParameterFilter { $user -And $user.sso_customer_id -eq 'testcustomeridentifier' }
            $syncContext.UsersTeamViewerByEmail['user1@example.test'] | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Secondary Email Addresses' {
        BeforeAll {
            Mock Add-TeamViewerUser { }
            Mock Edit-TeamViewerUser { }
            Mock Disable-TeamViewerUser { }
        }

        It 'Should match users with secondary email address' {
            $testUserAd = @{
                Email           = 'user1@example.test'
                Name            = 'User 1'
                IsEnabled       = $true
                SecondaryEmails = @('user1_secondary@example.test')
            }
            $testUserTv = @{
                id     = '123';
                email  = 'user1_secondary@example.test';
                name   = 'User 1';
                active = $true
            }
            $syncContext = @{
                UsersActiveDirectory        = @($testUserAd)
                UsersActiveDirectoryByEmail = @{
                    'user1@example.test'           = $testUserAd
                    'user1_secondary@example.test' = $testUserAd
                }
                UsersTeamViewerByEmail      = @{
                    'user1_secondary@example.test' = $testUserTv
                }
            }
            $configuration = @{
                UseSecondaryEmails    = $true
                UseGeneratedPassword  = $true
                DeactivateUsers       = $true
                ActiveDirectoryGroups = @('Group1')
            }
            Invoke-SyncUser $syncContext $configuration { }
            # Users are the same, so no add/update/disable
            Assert-MockCalled Add-TeamViewerUser -Times 0 -Scope It
            Assert-MockCalled Edit-TeamViewerUser -Times 0 -Scope It
            Assert-MockCalled Disable-TeamViewerUser -Times 0 -Scope It
        }
    }
}

Describe 'Invoke-SyncConditionalAccess' {
    BeforeAll {
        Mock Write-SyncLog { }
        Mock Write-SyncProgress { }
        Mock Select-ActiveDirectoryCommonName { return 'TestGroup' }
        Mock Add-TeamViewerConditionalAccessGroupUser { }
        Mock Add-TeamViewerConditionalAccessGroup {
            return [pscustomobject]@{ name = 'TestGroup'; id = 'abc123' }
        }
        Mock Remove-TeamViewerConditionalAccessGroupUser { }
    }

    It 'Should create a conditional access group if not exists' {
        $syncContext = @{
            UsersActiveDirectoryByGroup   = @{ }
            UsersConditionalAccessByGroup = @{ }
            GroupsConditionalAccess       = @()
        }
        $configuration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        Invoke-SyncConditionalAccess $syncContext $configuration { }
        Assert-MockCalled Add-TeamViewerConditionalAccessGroup -Times 1 -Scope It `
            -ParameterFilter { $groupName -Eq 'TestGroup' }
    }

    It 'Should add new users to the conditional access group' {
        $syncContext = @{
            UsersActiveDirectoryByGroup   = @{
                'CN=TestGroup' = @(
                    [pscustomobject]@{ Email = 'user1@example.test' }
                )
            }
            UsersTeamViewerByEmail        = @{
                'user1@example.test' = [pscustomobject]@{ id = 'u123' }
            }
            UsersConditionalAccessByGroup = @{
                'ca123' = @()
            }
            GroupsConditionalAccess       = @(
                [pscustomobject]@{ id = 'ca123'; name = 'TestGroup' }
            )
        }
        $configuration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        Invoke-SyncConditionalAccess $syncContext $configuration { }
        Assert-MockCalled Add-TeamViewerConditionalAccessGroupUser -Times 1 -Scope It `
            -ParameterFilter { $groupID -Eq 'ca123' -And $userIDs -Eq @('u123') }
    }

    It 'Should create bulks of 50 when adding new users to the conditional access group' {
        $testTeamViewerUsers = @{}
        foreach ($count in 1..120) {
            $testTeamViewerUsers["user$count@example.test"] = [pscustomobject]@{ id = "u$count" }
        }
        $testTeamViewerUsers.Count | Should -Be 120
        $syncContext = @{
            UsersActiveDirectoryByGroup   = @{
                'CN=TestGroup' = @(1..120 | ForEach-Object { [pscustomobject]@{ Email = "user$_@example.test" } })
            }
            UsersTeamViewerByEmail        = $testTeamViewerUsers
            UsersConditionalAccessByGroup = @{
                'ca123' = @()
            }
            GroupsConditionalAccess       = @(
                [pscustomobject]@{ id = 'ca123'; name = 'TestGroup' }
            )
        }
        $configuration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        Invoke-SyncConditionalAccess $syncContext $configuration { }
        Assert-MockCalled Add-TeamViewerConditionalAccessGroupUser -Times 3 -Scope It
        Assert-MockCalled Add-TeamViewerConditionalAccessGroupUser -Times 2 -Scope It `
            -ParameterFilter { $groupID -Eq 'ca123' -And $userIDs.Count -Eq 50 }
        Assert-MockCalled Add-TeamViewerConditionalAccessGroupUser -Times 1 -Scope It `
            -ParameterFilter { $groupID -Eq 'ca123' -And $userIDs.Count -Eq 20 }
    }

    It 'Should skip existing members of the conditional access group' {
        $syncContext = @{
            UsersActiveDirectoryByGroup   = @{
                'CN=TestGroup' = @(
                    [pscustomobject]@{ Email = 'user1@example.test' }
                )
            }
            UsersTeamViewerByEmail        = @{
                'user1@example.test' = [pscustomobject]@{ id = 'u123' }
            }
            UsersConditionalAccessByGroup = @{
                'ca123' = @('u123')
            }
            GroupsConditionalAccess       = @(
                [pscustomobject]@{ id = 'ca123'; name = 'TestGroup' }
            )
        }
        $configuration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        Invoke-SyncConditionalAccess $syncContext $configuration { }
        Assert-MockCalled Add-TeamViewerConditionalAccessGroupUser -Times 0 -Scope It
        Assert-MockCalled Remove-TeamViewerConditionalAccessGroupUser -Times 0 -Scope It
    }

    It 'Should remove unknown members from the conditional access group' {
        $syncContext = @{
            UsersActiveDirectoryByGroup   = @{
                'CN=TestGroup' = @()
            }
            UsersTeamViewerByEmail        = @{
                'user1@example.test' = [pscustomobject]@{ id = 'u123' }
                'user2@example.test' = [pscustomobject]@{ id = 'u456' }
            }
            UsersConditionalAccessByGroup = @{
                'ca123' = @('u123', 'u456')
            }
            GroupsConditionalAccess       = @(
                [pscustomobject]@{ id = 'ca123'; name = 'TestGroup' }
            )
        }
        $configuration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        Invoke-SyncConditionalAccess $syncContext $configuration { }
        Assert-MockCalled Remove-TeamViewerConditionalAccessGroupUser -Times 1 -Scope It `
            -ParameterFilter {
            $groupID -Eq 'ca123' -And $userIDs -And `
                $userIDs.Contains('u123') -And $userIDs.Contains('u456')
        }
    }

    It 'Should create bulks of 50 when removing members from the conditional access group' {
        $syncContext = @{
            UsersActiveDirectoryByGroup   = @{
                'CN=TestGroup' = @()
            }
            UsersTeamViewerByEmail        = @{}
            UsersConditionalAccessByGroup = @{
                'ca123' = @(1..120 | ForEach-Object { "u@$_" })
            }
            GroupsConditionalAccess       = @(
                [pscustomobject]@{ id = 'ca123'; name = 'TestGroup' }
            )
        }
        $configuration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        Invoke-SyncConditionalAccess $syncContext $configuration { }
        Assert-MockCalled Remove-TeamViewerConditionalAccessGroupUser -Times 3 -Scope It
        Assert-MockCalled Remove-TeamViewerConditionalAccessGroupUser -Times 2 -Scope It `
            -ParameterFilter { $userIDs.Count -Eq 50 }
        Assert-MockCalled Remove-TeamViewerConditionalAccessGroupUser -Times 1 -Scope It `
            -ParameterFilter { $userIDs.Count -Eq 20 }
    }
}

Describe 'Invoke-SyncUserGroups' {
    BeforeAll {
        Mock Write-SyncLog { }
        Mock Write-SyncProgress { }
        Mock Select-ActiveDirectoryCommonName { return 'TestGroup' }
        Mock Add-TeamViewerUserGroup {
            return [pscustomobject]@{ name = 'TestGroup'; id = 'foo123' }
        }
        Mock Add-TeamViewerUserGroupMember { }
        Mock Remove-TeamViewerUserGroupMember { }
    }

    It 'Should create a user group if not exists' {
        $testSyncContext = @{
            UsersActiveDirectoryByGroup = @{}
            UserGroups                  = @()
            UserGroupMembersByGroup     = @{}
        }
        $testConfiguration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        $result = Invoke-SyncUserGroups $testSyncContext $testConfiguration {}
        $result.Statistics.CreatedGroups | Should -Be 1
        Assert-MockCalled Add-TeamViewerUserGroup -Times 1 -Scope It `
            -ParameterFilter { $groupName -Eq 'TestGroup' }
    }

    It 'Should add users to the user group' {
        $testSyncContext = @{
            UsersActiveDirectoryByGroup = @{
                'CN=TestGroup' = @(
                    [pscustomobject]@{ Email = 'user1@example.test' }
                )
            }
            UsersTeamViewerByEmail      = @{
                'user1@example.test' = [pscustomobject]@{ id = 'u123' }
            }
            UserGroups                  = @(
                [pscustomobject]@{ id = 11223344; name = 'TestGroup' }
            )
            UserGroupMembersByGroup     = @{
                11223344 = @()
            }
        }
        $testConfiguration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        $result = Invoke-SyncUserGroups $testSyncContext $testConfiguration {}
        $result.Statistics.AddedMembers | Should -Be 1
        Assert-MockCalled Add-TeamViewerUserGroupMember -Times 1 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 }
    }

    It 'Should create bulks of 100 when adding new members to a user group' {
        $testTeamViewerUsers = @{}
        foreach ($count in 1..220) {
            $testTeamViewerUsers["user$count@example.test"] = [pscustomobject]@{ id = "u$count" }
        }
        $testTeamViewerUsers.Count | Should -Be 220
        $testSyncContext = @{
            UsersActiveDirectoryByGroup = @{
                'CN=TestGroup' = @(1..220 | ForEach-Object { [pscustomobject]@{ Email = "user$_@example.test" } })
            }
            UsersTeamViewerByEmail      = $testTeamViewerUsers
            UserGroups                  = @(
                [pscustomobject]@{ id = 11223344; name = 'TestGroup' }
            )
            UserGroupMembersByGroup     = @{
                11223344 = @()
            }
        }
        $testConfiguration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        $result = Invoke-SyncUserGroups $testSyncContext $testConfiguration {}
        $result.Statistics.AddedMembers | Should -Be 220
        Assert-MockCalled Add-TeamViewerUserGroupMember -Times 3 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 }
        Assert-MockCalled Add-TeamViewerUserGroupMember -Times 2 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 -And $accountIDs.Count -Eq 100 }
        Assert-MockCalled Add-TeamViewerUserGroupMember -Times 1 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 -And $accountIDs.Count -Eq 20 }
    }

    It 'Should skip existing members of the user group' {
        $testSyncContext = @{
            UsersActiveDirectoryByGroup = @{
                'CN=TestGroup' = @(
                    [pscustomobject]@{ Email = 'user1@example.test' }
                )
            }
            UsersTeamViewerByEmail      = @{
                'user1@example.test' = [pscustomobject]@{ id = 'u123' }
            }
            UserGroups                  = @(
                [pscustomobject]@{ id = 11223344; name = 'TestGroup' }
            )
            UserGroupMembersByGroup     = @{
                11223344 = @( [pscustomobject]@{ accountId = 123 } )
            }
        }
        $testConfiguration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        $result = Invoke-SyncUserGroups $testSyncContext $testConfiguration {}
        $result.Statistics.NotChanged | Should -Be 1
        $result.Statistics.AddedMembers | Should -Be 0
        $result.Statistics.RemovedMembers | Should -Be 0
        Assert-MockCalled Add-TeamViewerUserGroupMember -Times 0 -Scope It
        Assert-MockCalled Remove-TeamViewerUserGroupMember -Times 0 -Scope It
    }

    It 'Should remove unknown members from the user group' {
        $testSyncContext = @{
            UsersActiveDirectoryByGroup = @{
                'CN=TestGroup' = @()
            }
            UsersTeamViewerByEmail      = @{}
            UserGroups                  = @(
                [pscustomobject]@{ id = 11223344; name = 'TestGroup' }
            )
            UserGroupMembersByGroup     = @{
                11223344 = @( [pscustomobject]@{ accountId = 123 } )
            }
        }
        $testConfiguration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        $result = Invoke-SyncUserGroups $testSyncContext $testConfiguration {}
        $result.Statistics.RemovedMembers | Should -Be 1
        Assert-MockCalled Remove-TeamViewerUserGroupMember -Times 1 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 -And $accountIDs.Contains(123) }
    }

    It 'Should create bulks of 100 when removing members from a user group' {
        $testUserGroupMembers = (1..220 | ForEach-Object {  [pscustomobject]@{ accountId = $_ } })
        $testUserGroupMembers.Count | Should -Be 220
        $testSyncContext = @{
            UsersActiveDirectoryByGroup = @{}
            UsersTeamViewerByEmail      = @{}
            UserGroups                  = @(
                [pscustomobject]@{ id = 11223344; name = 'TestGroup' }
            )
            UserGroupMembersByGroup     = @{
                11223344 = $testUserGroupMembers
            }
        }
        $testConfiguration = @{
            ActiveDirectoryGroups = @('CN=TestGroup')
        }
        $result = Invoke-SyncUserGroups $testSyncContext $testConfiguration {}
        $result.Statistics.RemovedMembers | Should -Be 220
        Assert-MockCalled Remove-TeamViewerUserGroupMember -Times 3 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 }
        Assert-MockCalled Remove-TeamViewerUserGroupMember -Times 2 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 -And $accountIDs.Count -Eq 100 }
        Assert-MockCalled Remove-TeamViewerUserGroupMember -Times 1 -Scope It `
            -ParameterFilter { $groupID -Eq 11223344 -And $accountIDs.Count -Eq 20 }
    }
}

Describe 'Invoke-Sync' {
    BeforeAll {
        Mock Invoke-SyncPrework { }
        Mock Invoke-SyncUser { }
        Mock Invoke-SyncConditionalAccess { }
        Mock Invoke-SyncUserGroups { }
    }

    It 'Should call the user sync operations' {
        Invoke-Sync @{ } { }
        Assert-MockCalled Invoke-SyncPrework -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncUser -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncConditionalAccess -Times 0 -Scope It
        Assert-MockCalled Invoke-SyncUserGroups -Times 0 -Scope It
    }

    It 'Should call the conditional access sync operation if configured' {
        Invoke-Sync @{EnableConditionalAccessSync = $true } { }
        Assert-MockCalled Invoke-SyncPrework -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncUser -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncConditionalAccess -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncUserGroups -Times 0 -Scope It
    }

    It 'Should call the user groups sync operation if configured' {
        Invoke-Sync @{EnableUserGroupsSync = $true } { }
        Assert-MockCalled Invoke-SyncPrework -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncUser -Times 1 -Scope It
        Assert-MockCalled Invoke-SyncConditionalAccess -Times 0 -Scope It
        Assert-MockCalled Invoke-SyncUserGroups -Times 1 -Scope It
    }
}

Describe 'ConvertTo-SyncUpdateUserChangeset' {

    It 'Should create a hash with all changes' {
        $userTv = @{
            active = $false
            name   = 'Old Name'
        }
        $userAD = @{
            IsEnabled = $true
            Name      = 'New Name'
        }
        $changeset = (ConvertTo-SyncUpdateUserChangeset $userTv $userAD)
        $changeset | Should -BeOfType 'System.Collections.Hashtable'
        $changeset.name | Should -Be 'New Name'
        $changeset.active | Should -Be $true
    }

    It 'Should create a hash with only changed fields' {
        $userTv = @{
            active = $true
            name   = 'Old Name'
        }
        $userAD = @{
            IsEnabled = $true
            Name      = 'New Name'
        }
        $changeset = (ConvertTo-SyncUpdateUserChangeset $userTv $userAD)
        $changeset | Should -BeOfType 'System.Collections.Hashtable'
        $changeset.name | Should -Be 'New Name'
        $changeset.active | Should -BeNullOrEmpty
    }

    It 'Should create a hash that indicates user activation' {
        $userTv = @{
            active = $false
            name   = 'Name'
        }
        $userAD = @{
            IsEnabled = $true
            Name      = 'Name'
        }
        $changeset = (ConvertTo-SyncUpdateUserChangeset $userTv $userAD)
        $changeset | Should -BeOfType 'System.Collections.Hashtable'
        $changeset.name | Should -BeNullOrEmpty
        $changeset.active | Should -Be $true
    }
}

Describe 'Resolve-TeamViewerAccount' {
    BeforeAll {
        $testSyncContext = @{
            UsersTeamViewerByEmail = @{
                'user1@example.test' = @{ email = 'user1@example.test'; name = 'Test User 1'; active = $true }
                'user2@example.test' = @{ email = 'user2@example.test'; name = 'Test User 2'; active = $true }
                'user3@example.test' = @{ email = 'user3@example.test'; name = 'Test User 3'; active = $true }
            }
        }
        $testConfig = @{}
        $null = $testSyncContext
        $null = $testConfig
    }

    It 'Should return the corresponding TeamViewer user from the sync context' {
        $testUserAd = @{ email = 'user2@example.test' }
        $result = $testUserAd | Resolve-TeamViewerAccount $testSyncContext $testConfig
        $result | Should -Not -BeNullOrEmpty
        $result.name | Should -Be 'Test User 2'
    }

    It 'Should fallback to lookup secondary email addresses of the user' {
        $testConfig = @{ UseSecondaryEmails = $true }
        $testUserAd = @{ email = 'another@example.test'; SecondaryEmails = @('user3@example.test') }
        $result = $testUserAd | Resolve-TeamViewerAccount $testSyncContext $testConfig
        $result | Should -Not -BeNullOrEmpty
        $result.name | Should -Be 'Test User 3'
    }

    It 'Should return nothing if no user can be mapped' {
        $testUserAd = @{ email = 'someone@example.test' }
        $result = $testUserAd | Resolve-TeamViewerAccount $testSyncContext $testConfig
        $result | Should -BeNullOrEmpty
    }
}