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

Write-Host "GameDir: $GameDir"
Write-Host "Project : $csproj"
& $dotnet.Source build $csproj -c Release --nologo -v:minimal "-p:GameDir=$GameDir"
if ($LASTEXITCODE -ne 0) { throw "Compile failed: exit $LASTEXITCODE" }

$dll = Join-Path $PSScriptRoot 'ProbablyAug.dll'
if (-not (Test-Path $dll)) { throw "DLL not found: $dll" }
Write-Host "Build OK: $dll"
