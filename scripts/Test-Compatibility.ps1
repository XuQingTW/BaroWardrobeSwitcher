param(
    [Parameter(Mandatory = $true)]
    [string] $BarotraumaInstallDir,

    [Parameter(Mandatory = $true)]
    [string] $LuaCsPublicizedDir,

    [switch] $RequireOptional
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "tools/CompatibilityProbe/CompatibilityProbe.csproj"

& dotnet build $project -c Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$probe = Join-Path $root "artifacts/tools/CompatibilityProbe/net8.0/CompatibilityProbe.dll"
$arguments = @($probe, $BarotraumaInstallDir, $LuaCsPublicizedDir)
if ($RequireOptional) { $arguments += "--require-optional" }

& dotnet @arguments
exit $LASTEXITCODE
