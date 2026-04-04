function Write-ESeriesPrtgError {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    @{
        prtg = @{
            error = 1
            text  = $Message
        }
    } | ConvertTo-Json -Depth 3
}

function Invoke-ESeriesPrtgPs7Wrapper {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('system', 'volume', 'pool', 'snaprepo', 'cg')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$ApiEp,

        [Parameter(Mandatory = $true)]
        [string]$ApiPort,

        [Parameter(Mandatory = $true)]
        [string]$SanSysId,

        [Parameter(Mandatory = $true)]
        [string]$Account,

        [Parameter(Mandatory = $true)]
        [string]$Password,

        [string]$Vol,
        [string]$Pool,
        [string]$CG,

        [string]$PwshPath = 'pwsh',
        [string]$SantricityModulePath
    )

    $backendPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-ESeriesPrtgPs7Backend.ps1'
    if (-not (Test-Path -LiteralPath $backendPath)) {
        Write-Output (Write-ESeriesPrtgError -Message "PowerShell 7 backend script was not found: $backendPath")
        exit 1
    }

    $resolvedPwsh = $PwshPath
    if (-not [System.IO.Path]::IsPathRooted($PwshPath)) {
        $pwshCommand = Get-Command -Name $PwshPath -ErrorAction SilentlyContinue
        if ($null -eq $pwshCommand) {
            Write-Output (Write-ESeriesPrtgError -Message "PowerShell 7 executable '$PwshPath' was not found. Install PowerShell 7 or provide -PwshPath.")
            exit 1
        }
        $resolvedPwsh = $pwshCommand.Source
    }

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File', $backendPath,
        '-Mode', $Mode,
        '-ApiEp', $ApiEp,
        '-ApiPort', $ApiPort,
        '-SanSysId', $SanSysId,
        '-Account', $Account,
        '-Password', $Password
    )

    if (-not [string]::IsNullOrWhiteSpace($Vol)) {
        $arguments += @('-Vol', $Vol)
    }

    if (-not [string]::IsNullOrWhiteSpace($Pool)) {
        $arguments += @('-Pool', $Pool)
    }

    if (-not [string]::IsNullOrWhiteSpace($CG)) {
        $arguments += @('-CG', $CG)
    }

    if (-not [string]::IsNullOrWhiteSpace($SantricityModulePath)) {
        $arguments += @('-SantricityModulePath', $SantricityModulePath)
    }

    $output = & $resolvedPwsh @arguments
    if ($null -ne $output) {
        $output
    }

    if ($LASTEXITCODE -ne 0 -and $null -eq $output) {
        Write-Output (Write-ESeriesPrtgError -Message "PowerShell 7 backend failed for mode '$Mode'.")
    }

    exit $LASTEXITCODE
}