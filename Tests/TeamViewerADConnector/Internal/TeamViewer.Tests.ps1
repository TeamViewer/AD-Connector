# Copyright (c) 2018-2021 TeamViewer Germany GmbH
# See file LICENSE

BeforeAll {
    . "$PSScriptRoot\..\..\..\TeamViewerADConnector\Internal\TeamViewer.ps1"
}

Describe 'Invoke-TeamViewerRestMethod' {

    It 'Should pass through arguments and result' {
        Mock -CommandName Invoke-RestMethod -MockWith { return 123 }
        Invoke-TeamViewerRestMethod -Uri 'https://example.test' -Method Get | Should -Be 123
        Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -And $Uri -eq 'https://example.test' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should convert error payload' {
        $testError = (@{ message = 'Some Error' })
        Mock -CommandName Invoke-RestMethod -MockWith { Throw ($testError | ConvertTo-Json) }
        Mock -CommandName ConvertTo-TeamViewerRestError -MockWith { return $testError }
        { Invoke-TeamViewerRestMethod -Uri 'https://example.test' -Method Get } | Should -Throw "$testError*"
        Assert-MockCalled Invoke-RestMethod -Times 1
        Assert-MockCalled ConvertTo-TeamViewerRestError -Times 1
    }

    It 'Should call Invoke-WebRequest for PUT and DELETE methods' {
        Mock -CommandName Invoke-RestMethod -MockWith { return 123 }
        Mock -CommandName Invoke-WebRequest -MockWith { return @{Content = '{"value":456}' } }
        Invoke-TeamViewerRestMethod -Uri 'https://example.test' -Method Get | Should -Be 123
        Invoke-TeamViewerRestMethod -Uri 'https://example.test' -Method Post | Should -Be 123
        (Invoke-TeamViewerRestMethod -Uri 'https://example.test' -Method Put).value | Should -Be 456
        (Invoke-TeamViewerRestMethod -Uri 'https://example.test' -Method Delete).value | Should -Be 456
        Assert-MockCalled Invoke-RestMethod -Times 2 -Scope It
        Assert-MockCalled Invoke-WebRequest -Times 2 -Scope It
    }
}

Describe 'Invoke-TeamViewerPing' {

    It 'Should call the API ping REST endpoint' {
        Mock -CommandName Invoke-RestMethod -MockWith { return @{token_valid = $true } }
        Invoke-TeamViewerPing 'TestAccessToken' | Should -Be $true
        Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/ping' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should return false for invalid tokens' {
        Mock -CommandName Invoke-RestMethod -MockWith { return @{token_valid = $false } }
        Invoke-TeamViewerPing 'TestAccessToken' | Should -Be $false
    }

    It 'Should set the authorization header' {
        Mock -CommandName Invoke-RestMethod -MockWith { return @{token_valid = $true } }
        Invoke-TeamViewerPing 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Get-TeamViewerUser' {
    BeforeAll {
        Mock -CommandName Invoke-RestMethod -MockWith { return @{
                'users' = @(
                    @{ email = 'test1@example.test'; name = 'Test User1' },
                    @{ email = 'test2@example.test'; name = 'Test User2' },
                    @{ email = 'test3@example.test'; name = 'Test User3' }
                )
            } }
    }

    It 'Should call the API users endpoint' {
        Get-TeamViewerUser 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/users' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should return a dictionary of users by their email addresses' {
        $result = (Get-TeamViewerUser 'TestAccessToken')
        $result.Keys | Should -Contain 'test1@example.test'
        $result.Keys | Should -Contain 'test2@example.test'
        $result.Keys | Should -Contain 'test3@example.test'
        $result['test1@example.test'].Keys | Should -Contain 'name'
        $result['test1@example.test'].name | Should -Be 'Test User1'
    }

    It 'Should set the authorization header' {
        Get-TeamViewerUser 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Add-TeamViewerUser' {
    BeforeAll {
        $testUser = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
        $lastMockParams = @{ }
        Mock -CommandName Invoke-RestMethod -MockWith {
            $lastMockParams.Body = $Body
            return $testUser
        }
    }

    It 'Should call the API users endpoint' {
        $inputData = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test'; 'language' = 'en' }
        Add-TeamViewerUser 'TestAccessToken' $inputData | Should -Be $testUser
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/users' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should throw if required fields are missing' {
        $inputDatas = @(
            @{ 'email' = 'test1@example.test'; 'language' = 'en' }, # missing 'name'
            @{ 'name' = 'Test User 1'; 'language' = 'en' }, # missing 'email'
            @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' } # missing 'language'
        )
        $inputDatas | ForEach-Object { { Add-TeamViewerUser 'TestAccessToken' $_ } | Should -Throw }
    }

    It 'Should encode the payload using UTF-8' {
        $inputData = @{ 'name' = 'Test User Müller'; 'email' = 'test1@example.test'; 'language' = 'en' }
        Add-TeamViewerUser 'TestAccessToken' $inputData
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) } | Should -Not -Throw
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json } | Should -Not -Throw
        ([System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json).name | Should -Be 'Test User Müller'
    }

    It 'Should set the authorization header' {
        $inputData = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test'; 'language' = 'en' }
        Add-TeamViewerUser 'TestAccessToken' $inputData
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Edit-TeamViewerUser' {
    BeforeAll {
        $testUser = @{ 'id' = '1234'; 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
        Mock -CommandName Invoke-WebRequest -MockWith { return @{Content = $testUser | ConvertTo-Json } }
    }

    It 'Should call the API users endpoint' {
        $inputData = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
        $result = (Edit-TeamViewerUser 'TestAccessToken' 1234 $inputData)
        $result.id | Should -Be $testUser.id
        $result.name | Should -Be $testUser.name
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/users/1234' -And
            $Method -And $Method -eq 'Put'
        }
    }

    It 'Should set the authorization header' {
        $inputData = @{ 'name' = 'Test User 1'; 'email' = 'test1@example.test' }
        Edit-TeamViewerUser 'TestAccessToken' 1234 $inputData
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Disable-TeamViewerUser' {
    BeforeAll {
        $lastMockParams = @{ }
        Mock -CommandName Invoke-WebRequest -MockWith {
            $lastMockParams.Body = $Body
            return @{Content = "" }
        }
    }

    It 'Should call the API users endpoint' {
        Disable-TeamViewerUser 'TestAccessToken' 1234
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/users/1234' -And
            $Method -And $Method -eq 'Put'
        }
    }

    It 'Should set the payload parameter active to false' {
        Disable-TeamViewerUser 'TestAccessToken' 1234
        { [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json } | Should -Not -Throw
        ([System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json).active | Should -Be $false
    }

    It 'Should set the authorization header' {
        Disable-TeamViewerUser 'TestAccessToken' 1234
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }
}

Describe 'Get-TeamViewerAccount' {
    It 'Should call the API account endpoint' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerAccount 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/account' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should set the authorization header' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerAccount 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should throw on error if parameter NoThrow is not set' {
        Mock -CommandName Invoke-RestMethod -MockWith { Throw 'failure' }
        { Get-TeamViewerAccount 'TestAccessToken' } | Should -Throw
    }

    It 'Should not throw on error if parameter NoThrow is set' {
        Mock -CommandName Invoke-RestMethod -MockWith { Throw 'failure' }
        { Get-TeamViewerAccount 'TestAccessToken' -NoThrow } | Should -Not -Throw
    }
}

Describe 'Get-TeamViewerConditionalAccessGroup' {
    It 'Should call the API conditionalaccess endpoint' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerConditionalAccessGroup 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/conditionalaccess/directorygroups' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should set the authorization header' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerConditionalAccessGroup 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should do paging using the given continuation token' {
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                directory_groups   = @(
                    @{ id = '123'; name = 'Group 1' },
                    @{ id = '456'; name = 'Group 2' }
                );
                continuation_token = 'token1';
            } }
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                directory_groups = @(
                    @{ id = '789'; name = 'Group 3' }
                );
            } } -ParameterFilter { $Body.continuation_token -Eq 'token1' }
        $result = @(Get-TeamViewerConditionalAccessGroup 'TestAccessToken')
        $result | Should -HaveCount 3
        Assert-MockCalled Invoke-RestMethod -Times 2 -Scope It
    }
}

Describe 'Add-TeamViewerConditionalAccessGroup' {
    BeforeAll {
        $testGroup = @{ 'groupId' = '706e0f01-d152-4e25-a417-d62fe3796044'; 'groupName' = 'test group name' }
        $lastMockParams = @{ }
        Mock -CommandName Invoke-RestMethod -MockWith {
            $lastMockParams.Body = $Body
            return $testGroup
        }
    }

    It 'Should call the API conditionalaccess endpoint' {
        Add-TeamViewerConditionalAccessGroup 'TestAccessToken' 'test group name'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/conditionalaccess/directorygroups' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should set the authorization header' {
        Add-TeamViewerConditionalAccessGroup 'TestAccessToken' 'test group name'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should encode the payload using UTF-8' {
        Add-TeamViewerConditionalAccessGroup 'TestAccessToken' 'Test Group Müller'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        $payload = [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json
        $payload.name | Should -Be 'Test Group Müller'
    }
}

Describe 'Get-TeamViewerConditionalAccessGroupUser' {
    It 'Should call the API conditionalaccess user endpoint' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/conditionalaccess/directorygroups/0713e6bd-4bae-4067-93ad-c2ac8c66d469/users' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should set the authorization header' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should do paging using the given continuation token' {
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                directory_group    = @{
                    user_ids = @( 'u123', 'u456' )
                };
                continuation_token = 'token1';
            } }
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                directory_group = @{
                    user_ids = @( 'u789' )
                };
            } } -ParameterFilter { $Body.continuation_token -Eq 'token1' }
        $result = @(Get-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469')
        $result | Should -HaveCount 3
        Assert-MockCalled Invoke-RestMethod -Times 2 -Scope It
    }
}

Describe 'Add-TeamViewerConditionalAccessGroupUser' {
    BeforeAll {
        $lastMockParams = @{ }
        Mock -CommandName Invoke-RestMethod -MockWith {
            $lastMockParams.Body = $Body
        }
    }

    It 'Should call the API conditionalaccess members endpoint' {
        Add-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469' 'u1234'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/conditionalaccess/directorygroups/0713e6bd-4bae-4067-93ad-c2ac8c66d469' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should set the authorization header' {
        Add-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469' 'u1234'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should encode the payload using UTF-8' {
        Add-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469' @('u1234', 'u5678')
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        $payload = [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json
        $payload.member_type | Should -Be 'User'
        $payload.members | Should -HaveCount 2
        $payload.members | Should -Contain 'u1234'
        $payload.members | Should -Contain 'u5678'
    }
}

Describe 'Remove-TeamViewerConditionalAccessGroupUser' {
    BeforeAll {
        $lastMockParams = @{ }
        Mock -CommandName Invoke-WebRequest -MockWith {
            $lastMockParams.Body = $Body
            return @{Content = '' }
        }
    }

    It 'Should call the API conditionalaccess members endpoint' {
        Remove-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469' 'u1234'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/conditionalaccess/directorygroups/0713e6bd-4bae-4067-93ad-c2ac8c66d469/members' -And
            $Method -And $Method -eq 'Delete'
        }
    }

    It 'Should set the authorization header' {
        Remove-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469' 'u1234'
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should encode the payload using UTF-8' {
        Remove-TeamViewerConditionalAccessGroupUser 'TestAccessToken' '0713e6bd-4bae-4067-93ad-c2ac8c66d469' @('u1234', 'u5678')
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter { $Body }
        $payload = [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json
        $payload.member_type | Should -Be 'User'
        $payload.members | Should -HaveCount 2
        $payload.members | Should -Contain 'u1234'
        $payload.members | Should -Contain 'u5678'
    }
}

Describe 'Get-TeamViewerUserGroup' {
    It 'Should call the API usergroups endpoint' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerUserGroup 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/usergroups' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should set the authorization header' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerUserGroup 'TestAccessToken'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should do paging using the given pagination token' {
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                resources           = @(
                    @{ id = 112233; name = 'User Group 1' },
                    @{ id = 445566; name = 'User Group 2' }
                )
                nextPaginationToken = 'token1'
            } }
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                resources = @(
                    @{ id = 778899; name = 'User Group 3' }
                )
            } } -ParameterFilter { $Body.paginationToken -Eq 'token1' }
        $result = @(Get-TeamViewerUserGroup 'TestAccessToken')
        $result | Should -HaveCount 3
        Assert-MockCalled Invoke-RestMethod -Times 2 -Scope It
    }
}

Describe 'Add-TeamViewerUserGroup' {
    BeforeAll {
        $testGroup = @{ 'id' = 11223344; 'groupName' = 'test user group name' }
        $lastMockParams = @{ }
        Mock -CommandName Invoke-RestMethod -MockWith {
            $lastMockParams.Body = $Body
            return $testGroup
        }
    }

    It 'Should call the API usergroups endpoint' {
        Add-TeamViewerUserGroup 'TestAccessToken' 'test user group name'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/usergroups' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should set the authorization header' {
        Add-TeamViewerUserGroup 'TestAccessToken' 'test user group name'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should encode the payload using UTF-8' {
        Add-TeamViewerUserGroup 'TestAccessToken' 'Test Group Müller'
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        $payload = [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json
        $payload.name | Should -Be 'Test Group Müller'
    }
}

Describe 'Get-TeamViewerUserGroupMember' {
    It 'Should call the API usergroups endpoint' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerUserGroupMember 'TestAccessToken' 112233
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/usergroups/112233/members' -And
            $Method -And $Method -eq 'Get'
        }
    }

    It 'Should set the authorization header' {
        Mock -CommandName Invoke-RestMethod -MockWith { }
        Get-TeamViewerUserGroupMember 'TestAccessToken' 112233
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should do paging using the given pagination token' {
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                resources           = @(
                    @{ accountId = 123; name = 'User 1' },
                    @{ accountId = 456; name = 'User 2' }
                )
                nextPaginationToken = 'token1'
            } }
        Mock -CommandName Invoke-RestMethod -MockWith { @{
                resources = @(
                    @{ accountId = 789; name = 'User 3' }
                )
            } } -ParameterFilter { $Body.paginationToken -Eq 'token1' }
        $result = @(Get-TeamViewerUserGroupMember 'TestAccessToken' 112233)
        $result | Should -HaveCount 3
        Assert-MockCalled Invoke-RestMethod -Times 2 -Scope It
    }
}

Describe 'Add-TeamViewerUserGroupMember' {
    BeforeAll {
        $lastMockParams = @{ }
        Mock -CommandName Invoke-RestMethod -MockWith {
            $lastMockParams.Body = $Body
        }
    }

    It 'Should call the API usergroups endpoint' {
        Add-TeamViewerUserGroupMember 'TestAccessToken' 112233 @(456)
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/usergroups/112233/members' -And
            $Method -And $Method -eq 'Post'
        }
    }

    It 'Should set the authorization header' {
        Add-TeamViewerUserGroupMember 'TestAccessToken' 112233 @(456)
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should encode the payload using UTF-8' {
        Add-TeamViewerUserGroupMember 'TestAccessToken' 112233 @(456, 789)
        Assert-MockCalled Invoke-RestMethod -Times 1 -Scope It -ParameterFilter { $Body }
        $payload = [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json
        $payload | Should -Contain 456
        $payload | Should -Contain 789
    }
}

Describe 'Remove-TeamViewerUserGroupMember' {
    BeforeAll {
        $lastMockParams = @{ }
        Mock -CommandName Invoke-WebRequest -MockWith {
            $lastMockParams.Body = $Body
            return @{ Content = '' }
        }
    }

    It 'Should call the API usergroups endpoint' {
        Remove-TeamViewerUserGroupMember 'TestAccessToken' 112233 @(456)
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Uri -And [System.Uri]$Uri.PathAndQuery -eq '/api/v1/usergroups/112233/members' -And
            $Method -And $Method -eq 'Delete'
        }
    }

    It 'Should set the authorization header' {
        Remove-TeamViewerUserGroupMember 'TestAccessToken' 112233 @(456)
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter {
            $Headers -And $Headers.ContainsKey('authorization') -And $Headers.authorization -eq 'Bearer TestAccessToken'
        }
    }

    It 'Should encode the payload using UTF-8' {
        Remove-TeamViewerUserGroupMember 'TestAccessToken' 112233 @(456, 789)
        Assert-MockCalled Invoke-WebRequest -Times 1 -Scope It -ParameterFilter { $Body }
        $payload = [System.Text.Encoding]::UTF8.GetString($lastMockParams.Body) | ConvertFrom-Json
        $payload | Should -Contain 456
        $payload | Should -Contain 789
    }
}
