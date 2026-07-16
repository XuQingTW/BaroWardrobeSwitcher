param(
    [Parameter(Mandatory = $true)]
    [string] $BarotraumaInstallDir
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "tools/LuaSyntaxCheck/LuaSyntaxCheck.csproj"

& dotnet build $project -c Release "-p:BarotraumaInstallDir=$BarotraumaInstallDir"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$runner = Join-Path $root "artifacts/tools/LuaSyntaxCheck/net8.0/LuaSyntaxCheck.dll"
& dotnet $runner (Join-Path $root "Lua")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$tests = Get-ChildItem -LiteralPath (Join-Path $root "Lua/Tests") -Filter "*Tests.lua" -File -ErrorAction SilentlyContinue
foreach ($test in $tests) {
    & dotnet $runner --execute $test.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

exit 0
