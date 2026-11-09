param(
    [string]$GameDir = ""
)

$ErrorActionPreference = 'Stop'

# Locate the game folder: explicit arg, sync config, then script dir/parent/grandparent.
if ([string]::IsNullOrWhiteSpace($GameDir)) {
    $cfg = Join-Path $env:USERPROFILE '.probably-aug\config.json'
    if (Test-Path $cfg) {
        try {
            $j = Get-Content $cfg -Raw | ConvertFrom-Json
            if ($j.GameDir) { $GameDir = $j.GameDir }
        } catch { }
    }
}
if ([string]::IsNullOrWhiteSpace($GameDir)) {
    $candidates = @(
        $PSScriptRoot,
        (Split-Path $PSScriptRoot -Parent),
        (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'Probably Stolen_Data\Managed\Assembly-CSharp.dll'))) {
            $GameDir = $c
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GameDir)) {
    throw "Game folder not found. Pass -GameDir <Probably Stolen root>."
}

$managed = Join-Path $GameDir 'Probably Stolen_Data\Managed'
if (-not (Test-Path (Join-Path $managed 'Assembly-CSharp.dll'))) {
    throw "Assembly-CSharp.dll not found: $managed"
}

$dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue)
if ($dotnet -eq $null) {
    throw "dotnet SDK not found. Install .NET SDK 8+."
}

$csproj = Join-Path $PSScriptRoot 'src\ProbablyAug.csproj'
if (-not (Test-Path $csproj)) {
    throw "csproj not found: $csproj"
}

# Build outside the mod folder so the game loader never sees duplicate DLLs.
$buildRoot = Join-Path $env:TEMP 'ProbablyAugBuild'
$objDir = Join-Path $buildRoot 'obj\'
$binDir = Join-Path $buildRoot 'bin\'
$outDir = Join-Path $buildRoot 'out\'

Write-Host "GameDir: $GameDir"
Write-Host "Project : $csproj"
& $dotnet.Source build $csproj -c Release --nologo -v:minimal `
    "-p:GameDir=$GameDir" `
    "-p:BaseIntermediateOutputPath=$objDir" `
    "-p:BaseOutputPath=$binDir" `
    "-p:OutputPath=$outDir"
if ($LASTEXITCODE -ne 0) { throw "Compile failed: exit $LASTEXITCODE" }

$built = Join-Path $outDir 'ProbablyAug.dll'
if (-not (Test-Path $built)) { throw "DLL not found: $built" }
Copy-Item -LiteralPath $built -Destination (Join-Path $PSScriptRoot 'ProbablyAug.dll') -Force
Write-Host "Build OK: $(Join-Path $PSScriptRoot 'ProbablyAug.dll')"
