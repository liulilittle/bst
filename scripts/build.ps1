#Requires -Version 5.1
<#
  bst -- Windows entry point: one command, correct builds.
  Windows sites (windows-msvc-*) build natively with the Visual Studio MSVC
  environment.  Linux and Android sites are delegated to WSL, running the very
  same bash scripts a Linux host (and CI) runs.

  Examples:
    .\scripts\build.ps1 openssl -Site windows-msvc-x64
    .\scripts\build.ps1 jemalloc -Site windows-msvc-x86 -Variant both
    .\scripts\build.ps1 openssl -All            # all Windows sites + WSL sites
    .\scripts\build.ps1 liburing -Site linux-aarch64
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet("openssl", "jemalloc", "liburing")]
    [string]$Lib,

    [string]$Site = "",
    [string]$Version = "",
    [ValidateSet("static", "shared", "both")]
    [string]$Variant = "static",
    [switch]$Test,
    [switch]$Clean,
    [switch]$SkipSmoke,
    [switch]$All,
    [switch]$ListSites,
    [string]$WslDistro = "Ubuntu-24.04",
    [switch]$NoWsl
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$MatrixFile = Join-Path $Root "ci\site-matrix.env"

function Fail([string]$msg) { Write-Host "bst: error: $msg" -ForegroundColor Red; exit 1 }
function Info([string]$msg) { Write-Host "bst: $msg" }

function Get-Sites {
    Get-Content $MatrixFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\|' } | ForEach-Object {
        $f = $_ -split '\|'
        [pscustomobject]@{
            Site   = $f[0]
            Triple = $f[1]
            Family = $f[2]
            Libs   = "$($f[7])".Trim()
        }
    }
}

function Get-SiteInfo([string]$key) {
    Get-Sites | Where-Object { $_.Site -eq $key } | Select-Object -First 1
}

function Find-Bash {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} "Git\bin\bash.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
        (Get-Command bash.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    ) | Where-Object { $_ -and (Test-Path $_) }
    if ($candidates.Count -eq 0) {
        Fail "Git Bash not found. Install Git for Windows (https://git-scm.com/download/win) and retry."
    }
    $candidates[0]
}

function Get-WslRepoPath {
    $drive = $Root.Substring(0, 1).ToLower()
    $rest = $Root.Substring(2) -replace '\\', '/'
    "/mnt/$drive$rest"
}

function Require-Wsl {
    if ($NoWsl) { Fail "this site needs Linux; -NoWsl was given, aborting. Remove -NoWsl or run inside WSL." }
    $raw = (& wsl.exe -l -q 2>$null | Out-String)
    $distros = $raw.Replace([string][char]0, '')
    if ($LASTEXITCODE -ne 0 -or $distros -notmatch [regex]::Escape($WslDistro)) {
        Fail "WSL distro '$WslDistro' not found. Install it: wsl --install -d $WslDistro  (or pass -WslDistro <name>)"
    }
}

function Import-VsEnv([string]$arch) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Fail "vswhere not found -- install Visual Studio 2022 with the 'Desktop development with C++' workload."
    }
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) { Fail "Visual Studio with C++ tools not found (vswhere returned nothing)." }
    # vcvarsall uses the canonical x64/x86/x64_arm64 arch spellings and is the
    # entry Microsoft documents for command-line use.
    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvars)) { Fail "vcvarsall.bat not found under $vsPath" }
    Info "loading MSVC environment: vcvarsall.bat $arch ($vsPath)"
    $envDump = cmd /c "call `"$vcvars`" $arch >nul 2>&1 && set"
    foreach ($line in $envDump) {
        if ($line -match '^([^=]+)=(.*)$') {
            Set-Item -Path ("env:" + $matches[1]) -Value $matches[2] -ErrorAction SilentlyContinue
        }
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        Fail "cl.exe still not in PATH after loading the VS environment (arch=$arch). For ARM64 targets install the MSVC ARM64 build tools component."
    }
    # publish MSBuild to the bash side: Git Bash's rebuilt PATH may not expose it
    $mb = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
    if (Test-Path $mb) { $env:BST_MSBUILD = $mb }
}

function Download-File([string]$url, [string]$dest) {
    # curl.exe ships with Windows 10+; it streams to disk, honors redirects,
    # resumes partial files and survives transient network stalls.
    $curl = Join-Path $env:SystemRoot "System32\curl.exe"
    if (-not (Test-Path $curl)) { $curl = "curl.exe" }
    Info "downloading $url"
    & $curl -fL -C - --retry 5 --retry-all-errors --retry-delay 2 --speed-limit 1024 --speed-time 60 -o "$dest" $url
    if ($LASTEXITCODE -ne 0) { Fail "download failed (curl rc=$LASTEXITCODE): $url" }
}

function Get-ToolsDir { Join-Path (Join-Path $Root ".cache") "tools" }

function Expand-Zip([string]$zip, [string]$dir) {
    # tar.exe (bsdtar, ships with Windows 10+) extracts the big portable
    # archives in seconds; Expand-Archive is the fallback.
    $tar = Join-Path $env:SystemRoot "System32\tar.exe"
    if (Test-Path $tar) {
        & $tar -xf $zip -C $dir
        if ($LASTEXITCODE -eq 0) { return }
    }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
}

function Ensure-Nasm {
    $found = Get-Command nasm.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $exe = $null
    if ($found) {
        $exe = Get-Item $found.Source
    } else {
        $tools = Get-ToolsDir
        New-Item -ItemType Directory -Force -Path $tools | Out-Null
        $dir = Join-Path $tools "nasm"
        $direct = Join-Path $dir "nasm-2.16.03\nasm.exe"
        if (Test-Path $direct) { $exe = Get-Item $direct }
        if (-not $exe) {
            $zip = Join-Path $tools "nasm-2.16.03-win64.zip"
            if (-not (Test-Path $zip)) {
                Info "NASM not found -- provisioning a portable copy into .cache\tools (no admin needed)"
                Download-File "https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/win64/nasm-2.16.03-win64.zip" "$zip"
            }
            Expand-Zip $zip $dir
            if (Test-Path $direct) { $exe = Get-Item $direct }
            if (-not $exe) {
                $exe = Get-ChildItem -Path $dir -Recurse -Filter nasm.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        }
    }
    if (-not $exe) { Fail "NASM not found/provisioning failed. Install manually: winget install NASM.NASM" }
    # Always publish the resolved directory: Git Bash's login profile rebuilds
    # PATH and would otherwise pick a different (broken) tool.
    $env:PATH = "$($exe.DirectoryName);$env:PATH"
    $env:BST_TOOLS_DIRS = "$($exe.DirectoryName);$($env:BST_TOOLS_DIRS)"
    Info "using NASM: $($exe.FullName)"
}

function Ensure-Perl {
    $found = Get-Command perl.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    $exe = $null
    if ($found) {
        $exe = Get-Item $found.Source
    } else {
        $tools = Get-ToolsDir
        New-Item -ItemType Directory -Force -Path $tools | Out-Null
        $dir = Join-Path $tools "strawberry"
        # The portable distribution extracts to perl\bin\perl.exe; probe the
        # deterministic path first (recursive scans of the ~600MB tree are slow).
        $direct = Join-Path $dir "perl\bin\perl.exe"
        if (Test-Path $direct) { $exe = Get-Item $direct }
        if (-not $exe) {
            $zip = Join-Path $tools "strawberry-perl-5.42.3.1-64bit-portable.zip"
            if (-not (Test-Path $zip)) {
                Info "Perl not found -- provisioning Strawberry Perl (portable) into .cache\tools (no admin needed)"
                Download-File "https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54231_64bit/strawberry-perl-5.42.3.1-64bit-portable.zip" "$zip"
            }
            Info "extracting Strawberry Perl (one-time, ~600MB extracted)..."
            # A complete tree carries this core module; a truncated/partial
            # extraction (interrupted runs) does not.  Retry once.
            $marker = Join-Path $dir "perl\lib\warnings\register.pm"
            for ($attempt = 1; $attempt -le 2; $attempt++) {
                if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                Expand-Zip $zip $dir
                if (Test-Path $marker) { break }
                Info "Perl extraction looks incomplete -- retrying"
            }
            if (Test-Path $direct) { $exe = Get-Item $direct }
        }
    }
    if (-not $exe) { Fail "Strawberry Perl not found/provisioning failed. Install manually: winget install StrawberryPerl.StrawberryPerl" }
    $env:PATH = "$($exe.DirectoryName);$env:PATH"
    $env:BST_TOOLS_DIRS = "$($exe.DirectoryName);$($env:BST_TOOLS_DIRS)"
    Info "using Perl: $($exe.FullName)"
}

function Invoke-BuildOnWindows([string]$site) {
    $arch = switch -Wildcard ($site) {
        "windows-msvc-x64"   { "x64"; break }
        "windows-msvc-x86"   { "x86"; break }
        "windows-msvc-arm64" { "x64_arm64"; break }
        default              { "x64" }
    }
    Import-VsEnv $arch

    if ($Lib -eq "openssl") { Ensure-Perl; Ensure-Nasm }

    $bash = Find-Bash
    $rootUnix = $Root -replace '\\', '/'
    $argsList = @("scripts/build.sh", $Lib, "--site", $site, "--variant", $Variant)
    if ($Version) { $argsList += @("--version", $Version) }
    if ($Test) { $argsList += "--test" }
    if ($Clean) { $argsList += "--clean" }
    if ($SkipSmoke) { $argsList += "--skip-smoke" }
    $cmd = "cd '$rootUnix' && bash " + ($argsList -join ' ')
    Info "run: $cmd"
    & $bash -lc $cmd
}

function Invoke-BuildOnWsl([string]$site) {
    Require-Wsl
    $wslRoot = Get-WslRepoPath
    $argsList = @("scripts/build.sh", $Lib, "--site", $site, "--variant", $Variant)
    if ($Version) { $argsList += @("--version", $Version) }
    if ($Test) { $argsList += "--test" }
    if ($Clean) { $argsList += "--clean" }
    if ($SkipSmoke) { $argsList += "--skip-smoke" }
    $cmd = "cd '$wslRoot' && bash " + ($argsList -join ' ')
    Info "run (WSL $WslDistro): $cmd"
    & wsl.exe -d $WslDistro -- bash -lc $cmd
}

# ---- main -----------------------------------------------------------------
if (-not $Lib -and -not $ListSites) {
    Write-Host "usage: build.ps1 <openssl|jemalloc|liburing> [-Site <site>] [-Version <v>] [-Variant static|shared|both] [-Test] [-Clean] [-SkipSmoke] [-All] [-ListSites] [-WslDistro <name>] [-NoWsl]"
    exit 2
}

if ($ListSites) {
    $bash = Find-Bash
    $rootUnix = $Root -replace '\\', '/'
    & $bash -lc "cd '$rootUnix' && bash scripts/build.sh $Lib --list-sites"
    exit $LASTEXITCODE
}

if ($All) {
    $fail = 0
    $windowsSites = @(Get-Sites | Where-Object { $_.Family -eq "windows" -and ($_.Libs -split '\s+') -contains $Lib })
    foreach ($s in $windowsSites) {
        Invoke-BuildOnWindows $s.Site
        if ($LASTEXITCODE -ne 0) { $fail++; Write-Host "bst: FAILED: $($s.Site)" -ForegroundColor Red }
    }
    if (-not $NoWsl) {
        $otherSites = @(Get-Sites | Where-Object { $_.Family -ne "windows" -and ($_.Libs -split '\s+') -contains $Lib })
        foreach ($s in $otherSites) {
            Invoke-BuildOnWsl $s.Site
            if ($LASTEXITCODE -ne 0) { $fail++; Write-Host "bst: FAILED: $($s.Site)" -ForegroundColor Red }
        }
    }
    if ($fail -gt 0) { Fail "$fail site(s) failed" }
    Info "all sites ok"
    exit 0
}

if (-not $Site) { $Site = "windows-msvc-x64" }
$info = Get-SiteInfo $Site
if (-not $info) { Fail "unknown site '$Site' (see ci/site-matrix.env)" }
if (-not (($info.Libs -split '\s+') -contains $Lib)) { Fail "site '$Site' does not support '$Lib' (supported: $($info.Libs))" }

if ($info.Family -eq "windows") {
    Invoke-BuildOnWindows $Site
} else {
    Invoke-BuildOnWsl $Site
}
exit $LASTEXITCODE
