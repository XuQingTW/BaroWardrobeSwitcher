param(
    [Parameter(Mandatory = $true)]
    [string] $BarotraumaInstallDir,

    [Parameter(Mandatory = $true)]
    [string] $LuaCsPublicizedDir,

    [string] $MonoGameAssemblyPath = "",

    [ValidateSet("Debug", "Release")]
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$arguments = @(
    "build",
    (Join-Path $root "CSharp/BaroWardrobeSwitcher.csproj"),
    "-c", $Configuration,
    "-p:BarotraumaInstallDir=$BarotraumaInstallDir",
    "-p:LuaCsPublicizedDir=$LuaCsPublicizedDir"
)
if (-not [string]::IsNullOrWhiteSpace($MonoGameAssemblyPath)) {
    $arguments += "-p:MonoGameAssemblyPath=$MonoGameAssemblyPath"
}

& dotnet @arguments
exit $LASTEXITCODE
