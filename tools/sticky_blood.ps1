param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("install", "uninstall")]
    [string]$Action,
    [string]$GamePath
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $Root "patches\v1.0.0.json"

function Get-Hash([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Normalize-Game([string]$Path) {
    $full = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
    if (Test-Path -LiteralPath (Join-Path $full "gameinfo.txt")) {
        $full = Split-Path -Parent $full
    }
    if (-not (Test-Path -LiteralPath (Join-Path $full "garrysmod\gameinfo.txt"))) {
        throw "Not a Garry's Mod folder: $full"
    }
    return $full
}

function Find-Game([string]$Requested) {
    if ($Requested) {
        return Normalize-Game $Requested
    }
    $steamRoots = New-Object System.Collections.Generic.List[string]
    try {
        $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
        if ($steamPath) { $steamRoots.Add($steamPath) }
    } catch {}
    $steamRoots.Add((Join-Path ${env:ProgramFiles(x86)} "Steam"))
    if ($env:ProgramFiles) { $steamRoots.Add((Join-Path $env:ProgramFiles "Steam")) }

    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steam in $steamRoots) {
        if (-not $steam -or -not (Test-Path -LiteralPath $steam)) { continue }
        $libraries.Add($steam)
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '^\s*"path"\s+"([^"]+)"') {
                    $libraries.Add($matches[1].Replace("\\", "\"))
                }
            }
        }
    }
    foreach ($library in $libraries) {
        $candidate = Join-Path $library "steamapps\common\GarrysMod"
        if (Test-Path -LiteralPath (Join-Path $candidate "garrysmod\gameinfo.txt")) {
            return Normalize-Game $candidate
        }
    }
    throw "Could not find Garry's Mod. Pass -GamePath 'C:\...\GarrysMod'."
}

function Convert-Hex([string]$Hex) {
    if (($Hex.Length % 2) -ne 0) { throw "Invalid hex string" }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return $bytes
}

function Get-Offset([string]$Value) {
    if ($Value.StartsWith("0x")) {
        return [Convert]::ToInt32($Value.Substring(2), 16)
    }
    return [Convert]::ToInt32($Value, 10)
}

function Write-Atomic([string]$Target, [byte[]]$Data, [string]$ExpectedHash) {
    $temp = "$Target.stickyblood.tmp.$PID"
    try {
        [IO.File]::WriteAllBytes($temp, $Data)
        if ((Get-Hash $temp) -ne $ExpectedHash) {
            throw "Generated file failed verification: $Target"
        }
        Move-Item -LiteralPath $temp -Destination $Target -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Get-Entries($Game, $Manifest, [bool]$Uninstalling) {
    $entries = @()
    foreach ($spec in $Manifest.files) {
        $target = Join-Path $Game ($spec.path.Replace("/", "\"))
        if (-not (Test-Path -LiteralPath $target)) { throw "Missing game file: $target" }
        $current = Get-Hash $target
        if ($current -ne $spec.pristine_sha256 -and $current -ne $spec.patched_sha256) {
            throw "Unsupported or modified file: $target`nRun Steam Verify, then try again."
        }
        $backup = Join-Path (Split-Path -Parent $target) $spec.backup
        if ($Uninstalling -and $current -eq $spec.patched_sha256) {
            if (-not (Test-Path -LiteralPath $backup) -or (Get-Hash $backup) -ne $spec.pristine_sha256) {
                throw "Verified v1 backup is missing or invalid: $backup"
            }
        }
        $entries += [PSCustomObject]@{ Spec = $spec; Target = $target; Backup = $backup; Current = $current }
    }
    return $entries
}

function Install-Addon([string]$Game) {
    $destination = Join-Path $Game "garrysmod\addons\sticky_blood"
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root "addon.json") -Destination $destination
    Copy-Item -LiteralPath (Join-Path $Root "lua") -Destination $destination -Recurse
    Write-Host "Installed addon: $destination"
}

try {
    if (Get-Process -Name "gmod" -ErrorAction SilentlyContinue) {
        throw "Garry's Mod is running. Fully quit it before continuing."
    }
    $game = Find-Game $GamePath
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    Write-Host "Game: $game"

    if ($Action -eq "install") {
        $entries = Get-Entries $game $manifest $false
        foreach ($entry in $entries) {
            $spec = $entry.Spec
            if ($entry.Current -eq $spec.patched_sha256) {
                if (-not (Test-Path -LiteralPath $entry.Backup)) {
                    $legacy = "$($entry.Target).bak"
                    if ((Test-Path -LiteralPath $legacy) -and (Get-Hash $legacy) -eq $spec.pristine_sha256) {
                        Copy-Item -LiteralPath $legacy -Destination $entry.Backup
                        Write-Host "Adopted verified backup: $($entry.Backup)"
                    }
                }
                Write-Host "Already patched: $($entry.Target)"
                continue
            }
            if (Test-Path -LiteralPath $entry.Backup) {
                if ((Get-Hash $entry.Backup) -ne $spec.pristine_sha256) {
                    throw "Refusing to overwrite invalid backup: $($entry.Backup)"
                }
            } else {
                Copy-Item -LiteralPath $entry.Target -Destination $entry.Backup
            }
            [byte[]]$data = [IO.File]::ReadAllBytes($entry.Target)
            foreach ($patch in $spec.patches) {
                $offset = Get-Offset $patch.offset
                [byte[]]$before = Convert-Hex $patch.before
                [byte[]]$after = Convert-Hex $patch.after
                if ($before.Length -ne $after.Length) { throw "Invalid patch at $($patch.offset)" }
                for ($i = 0; $i -lt $before.Length; $i++) {
                    if ($data[$offset + $i] -ne $before[$i]) {
                        throw "Unexpected bytes in $($entry.Target) at $($patch.offset)"
                    }
                }
                [Array]::Copy($after, 0, $data, $offset, $after.Length)
            }
            Write-Atomic $entry.Target $data $spec.patched_sha256
            Write-Host "Patched: $($entry.Target)"
        }
        Install-Addon $game
    } else {
        $entries = Get-Entries $game $manifest $true
        foreach ($entry in $entries) {
            if ($entry.Current -eq $entry.Spec.pristine_sha256) {
                Write-Host "Already restored: $($entry.Target)"
                continue
            }
            [byte[]]$data = [IO.File]::ReadAllBytes($entry.Backup)
            Write-Atomic $entry.Target $data $entry.Spec.pristine_sha256
            Remove-Item -LiteralPath $entry.Backup -Force
            Write-Host "Restored: $($entry.Target)"
        }
        $addon = Join-Path $game "garrysmod\addons\sticky_blood"
        if (Test-Path -LiteralPath $addon) {
            Remove-Item -LiteralPath $addon -Recurse -Force
            Write-Host "Removed addon: $addon"
        }
    }
    Write-Host "Done. Fully restart Garry's Mod."
    exit 0
} catch {
    Write-Error $_
    exit 1
}
