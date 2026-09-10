[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Verify')]
    [string]$Mode = 'Apply'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

$upstreamScriptPath = Join-Path `
    $repositoryRoot `
    'externals/upstream/install-dotnet.ps1'

$generatedScriptPath = Join-Path `
    $repositoryRoot `
    'externals/install-dotnet.ps1'

$patchPath = Join-Path `
    $repositoryRoot `
    'patches/install-dotnet.native-tools.patch'

foreach ($requiredPath in @($upstreamScriptPath, $patchPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file was not found: $requiredPath"
    }
}

if ($Mode -eq 'Verify') {
    $temporaryDirectory = Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        "setup-dotnet-patch-check-$([guid]::NewGuid())"

    try {
        New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null

        $temporaryScriptPath = Join-Path `
            $temporaryDirectory `
            'install-dotnet.ps1'

        Copy-Item `
            -LiteralPath $upstreamScriptPath `
            -Destination $temporaryScriptPath `
            -Force

        & git -C $repositoryRoot apply `
            --check `
            --directory=$temporaryDirectory `
            --whitespace=nowarn `
            $patchPath

        if ($LASTEXITCODE -ne 0) {
            throw "The native-tools patch does not apply cleanly to the pristine upstream installer."
        }

        & git -C $repositoryRoot apply `
            --directory=$temporaryDirectory `
            --whitespace=nowarn `
            $patchPath

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to apply the native-tools patch in the verification directory."
        }

        $generatedContents = Get-Content `
            -LiteralPath $generatedScriptPath `
            -Raw

        $expectedContents = Get-Content `
            -LiteralPath $temporaryScriptPath `
            -Raw

        if ($generatedContents -cne $expectedContents) {
            throw @"
externals/install-dotnet.ps1 does not match the result of applying
patches/install-dotnet.native-tools.patch to
externals/upstream/install-dotnet.ps1.

Run:

  pwsh ./scripts/sync-install-dotnet.ps1 -Mode Apply

Then commit the regenerated installer and patch changes.
"@
        }

        Write-Host 'install-dotnet.ps1 is synchronized with the upstream copy and native-tools patch.'
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
        }
    }

    return
}

Write-Host 'Restoring generated installer from pristine upstream copy.'

Copy-Item `
    -LiteralPath $upstreamScriptPath `
    -Destination $generatedScriptPath `
    -Force

Write-Host 'Checking that the native-tools patch applies cleanly.'

& git -C $repositoryRoot apply `
    --check `
    --whitespace=nowarn `
    $patchPath

if ($LASTEXITCODE -ne 0) {
    throw @"
The native-tools patch no longer applies cleanly to the pristine upstream installer.

The upstream script likely changed in an overlapping area. Update
patches/install-dotnet.native-tools.patch to match the new upstream script.
"@
}

Write-Host 'Applying native curl.exe and 7z.exe installer changes.'

& git -C $repositoryRoot apply `
    --whitespace=nowarn `
    $patchPath

if ($LASTEXITCODE -ne 0) {
    throw "Failed to apply patch: $patchPath"
}

Write-Host 'Generated externals/install-dotnet.ps1 successfully.'