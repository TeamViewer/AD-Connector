# Copyright (c) 2018-2021 TeamViewer Germany GmbH
# See file LICENSE

function Write-SyncLog {
    param([Parameter(ValueFromPipeline)] $message, [Parameter()] $Extra)
    Process {
        Write-Output -InputObject @{Date = (Get-Date); Message = $message; Extra = $Extra } -NoEnumerate
    }
}

function Format-SyncLog {
    Process {
        $entry = $_
        if ($entry -is [object] -And $entry -And $entry.Message) {
            "$("{0:yyyy-MM-dd HH:mm:ss}" -f $entry.Date) $($entry.Message)"
        }
        elseif ($entry -is [object] -And $entry -And $entry.Activity -And $entry.Statistics) {
            "$($entry.Statistics | Format-Table -AutoSize -HideTableHeaders | Out-String)"
            "Duration $($entry.Activity): $($entry.Duration)"
        }
        else { $_ }
    }
}

function Write-SyncProgress {
    param($Handler, $PercentComplete, $CurrentOperation)
    (& $Handler $PercentComplete $CurrentOperation) | Out-Null
}

function ConvertTo-SyncUpdateUserChangeset($userTV, $userAD) {
    $changeset = @{ }
    if (!$userTV -Or !$userAD) {
        return $changeset
    }
    if ($userAD.name -ne $userTV.name) { $changeset.name = $userAD.name }
    if ($userAD.IsEnabled -ne $userTV.active) { $changeset.active = $userAD.IsEnabled }
    return $changeset
}

function Format-SyncUpdateUserChangeset {
    param([Parameter(ValueFromPipeline)] $changeset)
    Process {
        $message = ""
        if ($changeset.name) { $message += "Changing name to '$($changeset.name)'. " }
        if ($changeset.active) { $message += "Changing account status to 'active'. " }
        "$message"
    }
}

function Split-Bulk {
    param([int]$Size)
    Begin { $bulk = New-Object System.Collections.ArrayList($Size) }
    Process { $bulk.Add($_) | Out-Null; if ($bulk.Count -ge $Size) { , $bulk.Clone(); $bulk.Clear() } }
    End { if ($bulk.Count -gt 0) { , $bulk } }
}

function Resolve-TeamViewerAccount {
    param($syncContext, $configuration, [Parameter(ValueFromPipeline)] $userAd)
    Process {
        $userTv = $syncContext.UsersTeamViewerByEmail[$userAd.email]
        if (!$userTv -and $configuration.UseSecondaryEmails) {
            $userTv = $userAd.SecondaryEmails | `
                ForEach-Object { $syncContext.UsersTeamViewerByEmail[$_] } | `
                Select-Object -First 1
        }
        Write-Output $userTv
    }
}

function Invoke-SyncPrework($syncContext, $configuration, $progressHandler) {
    # Fetch users from configured AD groups.
    # Map the AD user objects to all their email addresses.
    Write-SyncLog "Fetching members of configured Active Directory groups:"
    Write-SyncProgress -Handler $progressHandler -PercentComplete 5 -CurrentOperation 'GetActiveDirectoryGroupMembers'
    $usersAD = New-Object -TypeName System.Collections.Generic.List[System.Object]
    $usersADByEmail = @{ }
    $usersADByGroup = @{ }
    ForEach ($adGroup in $configuration.ActiveDirectoryGroups) {
        Write-SyncLog "Fetching members of Active Directory group '$adGroup'"
        $adGroupUsers = @(Get-ActiveDirectoryGroupMember $configuration.ActiveDirectoryRoot $configuration.RecursiveGroups $adGroup)
        $usersADByGroup[$adGroup] = $adGroupUsers
        if ($adGroupUsers) { $usersAD.AddRange($adGroupUsers) }
        ForEach ($adGroupUser in $adGroupUsers) {
            $usersADByEmail[$adGroupUser.Email] = $adGroupUser
            if ($configuration.UseSecondaryEmails) {
                $adGroupUser.SecondaryEmails | ForEach-Object { $usersADByEmail[$_] = $adGroupUser } | Out-Null
            }
        }
        Write-SyncLog "Retrieved $($adGroupUsers.Count) users from Active Directory group '$adGroup'"
    }

    # Filter only unique (email) AD users
    $usersAD = ($usersAD | Select-Object -Unique -Property `
        @{ Label = "AsString"; Expression = { "$($_.Email)" }; }, `
        @{ Label = "Value"; Expression = { $_ } } | Select-Object -ExpandProperty Value)
    $adGroupsCount = ($configuration.ActiveDirectoryGroups | Measure-Object).Count
    Write-SyncLog "Retrieved $($usersAD.Count) unique users from $adGroupsCount configured Active Directory groups."

    # Fetch users from the configured TeamViewer company.
    # Users are mapped to their email addresses.
    Write-SyncProgress -Handler $progressHandler -PercentComplete 10 'GetTeamViewerUsers'
    Write-SyncLog "Fetching TeamViewer company users"
    $usersTVByEmail = (Get-TeamViewerUser $configuration.ApiToken)
    Write-SyncLog "Retrieved $($usersTVByEmail.Count) TeamViewer company users"

    if ($configuration.EnableConditionalAccessSync) {
        # Fetch available conditional access groups
        Write-SyncProgress -Handler $progressHandler -PercentComplete 15 'GetTeamViewerConditionalAccess'
        Write-SyncLog "Fetching TeamViewer conditional access groups."
        $groupsCA = @(Get-TeamViewerConditionalAccessGroup $configuration.ApiToken)
        Write-SyncLog "Retrieved $($groupsCA.Count) TeamViewer conditional access groups."

        # Fetch users per group
        $usersCAByGroup = @{}
        ForEach ($groupCA in $groupsCA) {
            Write-SyncLog "Fetching members of TeamViewer conditional access group '$($groupCA.name)'"
            $usersCA = @(Get-TeamViewerConditionalAccessGroupUser $configuration.ApiToken $groupCA.id)
            Write-SyncLog "Retrieved $($usersCA.Count) members of TeamViewer conditional access group '$($groupCA.name)'"
            $usersCAByGroup[$groupCA.id] = $usersCA
        }
    }

    if ($configuration.EnableUserGroupsSync) {
        # Fetch all available user groups
        Write-SyncProgress -Handler $progressHandler -PercentComplete 20 'GetTeamViewerUserGroups'
        Write-SyncLog "Fetching list of TeamViewer user groups."
        $userGroups = @(Get-TeamViewerUserGroup $configuration.ApiToken)
        Write-SyncLog "Retrieved $($userGroups.Count) TeamViewer user groups."

        # Fetch user group members
        $userGroupMembersByGroup = @{}
        foreach ($userGroup in $userGroups) {
            Write-SyncLog "Fetching members of TeamViewer user group '$($userGroup.name)'"
            $userGroupMembers = @(Get-TeamViewerUserGroupMember $configuration.ApiToken $userGroup.id)
            Write-SyncLog "Retrieved $($userGroupMembers.Count) members of TeamViewer user group '$($userGroup.name)'"
            $userGroupMembersByGroup[$userGroup.id] = $userGroupMembers
        }
    }

    $syncContext.UsersActiveDirectory = $usersAD
    $syncContext.UsersActiveDirectoryByEmail = $usersADByEmail
    $syncContext.UsersActiveDirectoryByGroup = $usersADByGroup
    $syncContext.UsersTeamViewerByEmail = $usersTVByEmail
    $syncContext.GroupsConditionalAccess = $groupsCA
    $syncContext.UsersConditionalAccessByGroup = $usersCAByGroup
    $syncContext.UserGroups = $userGroups
    $syncContext.UserGroupMembersByGroup = $userGroupMembersByGroup
}

function Invoke-SyncUser($syncContext, $configuration, $progressHandler) {
    Write-SyncLog "Starting Active Directory user synchronization."
    if ($configuration.TestRun) {
        Write-SyncLog "Mode 'Test Run' is active. Information of your TeamViewer account will not be modified!"
    }

    $statistics = @{ Created = 0; Updated = 0; NotChanged = 0; Deactivated = 0; Failed = 0; }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Create/Update users in the TeamViewer company
    Write-SyncProgress -Handler $progressHandler -PercentComplete 50 -CurrentOperation 'CreateUpdateUser'
    ForEach ($userAd in $syncContext.UsersActiveDirectory) {
        $userTv = $userAd | Resolve-TeamViewerAccount $syncContext $configuration
        if ($userTv -and $userTv.active -and $userTv.name -eq $userAd.name) {
            Write-SyncLog "No changes for user $($userAd.email). Skipping."
            $statistics.NotChanged++
        }
        elseif ($userTv) {
            $changeset = (ConvertTo-SyncUpdateUserChangeset $userTv $userAd)
            Write-SyncLog "Updating user $($userAd.email): $($changeset | Format-SyncUpdateUserChangeset)" -Extra $changeset
            if (!$configuration.TestRun) {
                $updatedUser = $userAd.Clone()
                $updatedUser.active = $true
                try {
                    Edit-TeamViewerUser $configuration.ApiToken $userTv.id $updatedUser | Out-Null
                    $statistics.Updated++
                }
                catch {
                    Write-SyncLog "Failed to update TeamViewer user $($userAd.email): $_"
                    $statistics.Failed++
                }
            }
            else { $statistics.Updated++ }
        }
        else {
            Write-SyncLog "Creating user $($userAd.email)"
            if (!$configuration.TestRun) {
                $newUser = $userAd.Clone()
                $newUser.language = $configuration.UserLanguage
                if ($configuration.UseDefaultPassword) {
                    $newUser.password = $configuration.DefaultPassword
                }
                if ($configuration.UseGeneratedPassword) {
                    $newUser.password = ""
                }
                if ($configuration.UseSsoCustomerId) {
                    $newUser.sso_customer_id = $configuration.SsoCustomerId;
                }
                try {
                    $addedUser = (Add-TeamViewerUser $configuration.ApiToken $newUser)
                    $newUser.id = $addedUser.id
                    $syncContext.UsersTeamViewerByEmail[$newUser.email] = $newUser
                    $statistics.Created++
                }
                catch {
                    Write-SyncLog "Failed to create TeamViewer user $($userAd.email): $_"
                    $statistics.Failed++
                }
            }
            else {
                $syncContext.UsersTeamViewerByEmail[$userAd.email] = @{ id = 'u0'; email = $userAd.email }
                $statistics.Created++
            }
        }
    }

    # Deactivate TeamViewer users (if configured)
    Write-SyncProgress -Handler $progressHandler -PercentComplete 60 -CurrentOperation 'DeactivateUser'
    if ($configuration.DeactivateUsers) {
        # Try to fetch the account information of the configured TeamViewer API token.
        # This information is used to not accidentially deactivate the token owner,
        # which would block further processing of the script.
        Write-SyncLog "Trying to fetch account information of configured TeamViewer API token"
        $currentAccount = Get-TeamViewerAccount $configuration.ApiToken -NoThrow
        if (!$currentAccount) {
            Write-SyncLog "Unable to determine token account information. Please check API token permissions."
        }

        $usersUnknown = ($syncContext.UsersTeamViewerByEmail.Values | Where-Object { !$syncContext.UsersActiveDirectoryByEmail[$_.email] -And $_.active })
        ForEach ($user in $usersUnknown) {
            if ($currentAccount -And $currentAccount.email -eq $user.email) {
                Write-SyncLog "Skipping deactivation of TeamViewer user $($user.email), because it owns the configured TeamViewer API token."
                continue
            }

            Write-SyncLog "Deactivating TeamViewer user $($user.email)"
            if (!$configuration.TestRun) {
                try {
                    Disable-TeamViewerUser $configuration.ApiToken $user.id | Out-Null
                    $statistics.Deactivated++
                }
                catch {
                    Write-SyncLog "Failed to deactivate TeamViewer user $($user.email): $_"
                    $statistics.Failed++
                }
            }
            else { $statistics.Deactivated++ }
        }
    }

    $stopwatch.Stop()
    Write-SyncLog "Completed Active Directory user synchronization"

    # Return some statistics
    Write-Output @{
        Activity   = 'SyncUser'
        Statistics = $statistics
        Duration   = $stopwatch.Elapsed
    }
}

function Invoke-SyncConditionalAccess($syncContext, $configuration, $progressHandler) {
    Write-SyncLog "Starting TeamViewer conditional access group synchronization"
    if ($configuration.TestRun) {
        Write-SyncLog "Mode 'Test Run' is active. Information of your TeamViewer conditional access groups will not be modified!"
    }

    $statistics = @{ CreatedGroups = 0; AddedMembers = 0; RemovedMembers = 0; NotChanged = 0; Failed = 0; }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-SyncProgress -Handler $progressHandler -PercentComplete 70 -CurrentOperation 'ConditionalAccess'
    ForEach ($adGroup in $configuration.ActiveDirectoryGroups) {
        $adGroupName = ($adGroup | Select-ActiveDirectoryCommonName)
        $caGroup = ($syncContext.GroupsConditionalAccess | Where-Object { $_.name -eq $adGroupName } | Select-Object -First 1)

        # Try to create the conditional access group, if not exists
        if (!$caGroup) {
            Write-SyncLog "Creating conditional access group '$adGroupName'"
            if (!$configuration.TestRun) {
                try {
                    $caGroup = (Add-TeamViewerConditionalAccessGroup $configuration.ApiToken $adGroupName)
                    $statistics.CreatedGroups++
                }
                catch {
                    Write-SyncLog "Failed to create conditional access group '$adGroupName': $_"
                    $statistics.Failed++
                    Continue;
                }
            }
            else {
                $caGroup = @{ id = "$(New-Guid)"; name = $adGroupName; }
                $statistics.CreatedGroups++
            }
        }

        $usersAd = @($syncContext.UsersActiveDirectoryByGroup[$adGroup]) | Where-Object { $_ }
        $usersCa = @($syncContext.UsersConditionalAccessByGroup[$caGroup.id]) | Where-Object { $_ }

        # Map the AD group users to a TeamViewer users
        $usersTv = @($usersAd | Resolve-TeamViewerAccount $syncContext $configuration | Where-Object { $_ })

        # Add missing members to the conditional access group
        $usersToAdd = @()
        ForEach ($userTv in $usersTv) {
            $userCa = ($usersCa | Where-Object { $_ -Eq $userTv.id })
            if (!$userCa) {
                Write-SyncLog "User '$($userTv.email)' will be added to conditional access group '$($caGroup.name)'"
                $usersToAdd += $userTv.id
            }
            else {
                Write-SyncLog "User '$($userTv.email)' is already member of conditional access group '$($caGroup.name)'. Skipping."
                $statistics.NotChanged++
            }
        }
        Write-SyncLog "Adding $($usersToAdd.Count) users to conditional access group '$($caGroup.name)'"
        if (!$configuration.TestRun -And $usersToAdd.Count -Gt 0) {
            $usersToAdd | Split-Bulk -Size 50 | ForEach-Object {
                $currentUsersToAdd = $_
                try {
                    (Add-TeamViewerConditionalAccessGroupUser $configuration.ApiToken $caGroup.id $currentUsersToAdd) | Out-Null
                    $statistics.AddedMembers += $currentUsersToAdd.Count
                }
                catch {
                    Write-SyncLog "Failed to add members to conditional access group '$($caGroup.name)': $_"
                    $statistics.Failed += $currentUsersToAdd.Count
                }
            }
        }
        else { $statistics.AddedMembers += $usersToAdd.Count }

        # Remove unknown users from the conditional access group
        $usersToRemove = @()
        ForEach ($userCa in $usersCa) {
            $userTv = ($usersTv | Where-Object { $_.id -Eq $userCa })
            if (!$userTv) {
                Write-SyncLog "User '$($userCa)' will be removed from conditional access group '$($caGroup.name)'"
                $usersToRemove += $userCa
            }
        }
        Write-SyncLog "Removing $($usersToRemove.Count) users from conditional access group '$($caGroup.name)'"
        if (!$configuration.TestRun -And $usersToRemove.Count -Gt 0) {
            $usersToRemove | Split-Bulk -Size 50 | ForEach-Object {
                $currentUsersToRemove = $_
                try {
                    (Remove-TeamViewerConditionalAccessGroupUser $configuration.ApiToken $caGroup.id $currentUsersToRemove) | Out-Null
                    $statistics.RemovedMembers += $currentUsersToRemove.Count
                }
                catch {
                    Write-SyncLog "Failed to remove members from conditional access group '$($caGroup.name)': $_"
                    $statistics.Failed += $currentUsersToRemove.Count
                }
            }
        }
        else { $statistics.RemovedMembers += $usersToRemove.Count }
    }

    $stopwatch.Stop()
    Write-SyncLog "Completed TeamViewer conditional access group synchronization"

    # Return some statistics
    Write-Output @{
        Activity   = 'SyncConditionalAccess'
        Statistics = $statistics
        Duration   = $stopwatch.Elapsed
    }
}

function Invoke-SyncUserGroups($syncContext, $configuration, $progressHandler) {
    Write-SyncLog "Starting user groups synchronization"
    if ($configuration.TestRun) {
        Write-SyncLog "Mode 'Test Run' is active. Information of your TeamViewer user groups will not be modified!"
    }

    $statistics = @{ CreatedGroups = 0; AddedMembers = 0; RemovedMembers = 0; NotChanged = 0; Failed = 0; }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-SyncProgress -Handler $progressHandler -PercentComplete 80 -CurrentOperation 'UserGroups'

    foreach ($adGroup in $configuration.ActiveDirectoryGroups) {
        $adGroupName = ($adGroup | Select-ActiveDirectoryCommonName)
        $userGroup = ($syncContext.UserGroups | Where-Object { $_.name -eq $adGroupName } | Select-Object -First 1)

        # Try to create the user group, if no group with such name exists yet
        if (!$userGroup) {
            Write-SyncLog "Creating user group '$adGroupName'"
            if (!$configuration.TestRun) {
                try {
                    $userGroup = (Add-TeamViewerUserGroup $configuration.ApiToken $adGroupName)
                    $statistics.CreatedGroups++
                }
                catch {
                    Write-SyncLog "Failed to create user group '$adGroupName': $_"
                    $statistics.Failed++
                    continue
                }
            }
            else {
                $userGroup = @{ id = (Get-Random); name = $adGroupName; }
                $statistics.CreatedGroups++
            }
        }

        $usersAd = @($syncContext.UsersActiveDirectoryByGroup[$adGroup]) | Where-Object { $_ }
        $userGroupMembers = @($syncContext.UserGroupMembersByGroup[$userGroup.id]) | Where-Object { $_ }

        # Map the AD group users to a TeamViewer users
        $usersTv = @($usersAd | Resolve-TeamViewerAccount $syncContext $configuration | Where-Object { $_ })

        # Add missing members to the user group
        $membersToAdd = @()
        foreach ($userTv in $usersTv) {
            $userGroupMember = ($userGroupMembers | Where-Object { $_.accountId -Eq $userTv.id.Trim('u') })
            if (!$userGroupMember) {
                Write-SyncLog "User '$($userTv.email)' will be added to user group '$($userGroup.name)'"
                $membersToAdd += $userTv.id
            }
            else {
                Write-SyncLog "User '$($userTv.email)' is already member of user group '$($userGroup.name)'. Skipping."
                $statistics.NotChanged++
            }
        }
        Write-SyncLog "Adding $($membersToAdd.Count) users to user group '$($userGroup.name)'"
        if (!$configuration.TestRun -And $membersToAdd.Count -Gt 0) {
            $membersToAdd | Split-Bulk -Size 100 | ForEach-Object {
                $currentMembersToAdd = $_
                try {
                    (Add-TeamViewerUserGroupMember $configuration.ApiToken $userGroup.id $currentMembersToAdd) | Out-Null
                    $statistics.AddedMembers += $currentMembersToAdd.Count
                }
                catch {
                    Write-SyncLog "Failed to add members to user group '$($userGroup.name)': $_"
                    $statistics.Failed += $currentMembersToAdd.Count
                }
            }
        }
        else { $statistics.AddedMembers += $membersToAdd.Count }

        # Remove unknown members from the user group
        $membersToRemove = @()
        foreach ($userGroupMember in $userGroupMembers) {
            $userTv = ($usersTv | Where-Object { $_.id.Trim('u') -Eq $userGroupMember.accountId })
            if (!$userTv) {
                Write-SyncLog "User '$($userGroupMember.name)' will be removed from user group '$($userGroup.name)'"
                $membersToRemove += $userGroupMember.accountId
            }
        }
        Write-SyncLog "Removing $($membersToRemove.Count) members from user group '$($userGroup.name)'"
        if (!$configuration.TestRun -And $membersToRemove.Count -Gt 0) {
            $membersToRemove | Split-Bulk -Size 100 | ForEach-Object {
                $currentMembersToRemove = $_
                try {
                    (Remove-TeamViewerUserGroupMember $configuration.ApiToken $userGroup.id $currentMembersToRemove) | Out-Null
                    $statistics.RemovedMembers += $currentMembersToRemove.Count
                }
                catch {
                    Write-SyncLog "Failed to remove members from user group '$($userGroup.name)'"
                    $statistics.Failed += $currentMembersToRemove.Count
                }
            }
        }
        else { $statistics.RemovedMembers += $membersToRemove.Count }
    }

    $stopwatch.Stop()
    Write-SyncLog "Completed TeamViewer user group synchronization"

    # Return some statistics
    Write-Output @{
        Activity   = 'SyncUserGroups'
        Statistics = $statistics
        Duration   = $stopwatch.Elapsed
    }
}

function Invoke-Sync($configuration, $progressHandler) {
    Write-SyncLog ("-" * 50)
    Write-SyncLog "Starting synchronization run"
    Write-SyncLog "Version $ScriptVersion ($([environment]::OSVersion.VersionString), PS $($PSVersionTable.PSVersion))"

    if ($configuration.TestRun) {
        Write-SyncLog "Mode 'Test Run' is active!"
    }

    if (!$progressHandler) { $progressHandler = { } }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $syncContext = @{ }
    Invoke-SyncPrework -syncContext $syncContext -configuration $configuration -progressHandler $progressHandler
    Invoke-SyncUser -syncContext $syncContext -configuration $configuration -progressHandler $progressHandler
    if ($configuration.EnableConditionalAccessSync) {
        Invoke-SyncConditionalAccess -syncContext $syncContext -configuration $configuration -progressHandler $progressHandler
    }
    if ($configuration.EnableUserGroupsSync) {
        Invoke-SyncUserGroups -syncContext $syncContext -configuration $configuration -progressHandler $progressHandler
    }

    # We're done here
    $stopwatch.Stop()
    Write-SyncProgress -Handler $progressHandler -PercentComplete 100 'Completed'

    # Return some statistics
    Write-Output @{
        Activity   = 'Total'
        Statistics = @{}
        Duration   = $stopwatch.Elapsed
    }
}
