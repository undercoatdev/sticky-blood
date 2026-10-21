param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("install", "uninstall")]
    [string]$Action,
    [string]$GamePath,
    [switch]$DryRun,
    [switch]$SkipRunningCheck
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path (Join-Path $Root "patches") "v2.json"
$V1Path = Join-Path (Join-Path $Root "patches") "v1.0.0.json"

$Script:BranchRequired = "64-bit (x86-64 branch) required"
$Script:SteamVerify = "The installed files do not match the Sticky Blood backup. Run Steam Verify, then try again."

if (-not ("StickyBlood.SigScan" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
namespace StickyBlood {
    public static class SigScan {
        public static int[] FindAll(byte[] data, int[] pat) {
            int bestA = 0;
            int bestLen = 0;
            int i = 0;
            while (i < pat.Length) {
                if (pat[i] < 0) { i++; continue; }
                int j = i;
                while (j < pat.Length && pat[j] >= 0) j++;
                if (j - i > bestLen) { bestA = i; bestLen = j - i; }
                i = j;
            }
            if (bestLen < 4) {
                throw new InvalidOperationException("signature needs >=4 consecutive literal bytes");
            }
            var hits = new List<int>();
            int p = Array.IndexOf(data, (byte)pat[bestA], 0);
            while (p >= 0) {
                int origin = p - bestA;
                if (origin >= 0 && origin + pat.Length <= data.Length) {
                    bool ok = true;
                    for (int k = 0; k < pat.Length; k++) {
                        if (pat[k] >= 0 && data[origin + k] != (byte)pat[k]) { ok = false; break; }
                    }
                    if (ok) hits.Add(origin);
                }
                if (p + 1 >= data.Length) break;
                p = Array.IndexOf(data, (byte)pat[bestA], p + 1);
            }
            return hits.ToArray();
        }
    }
}
'@
}

function Throw-Sig([string]$Id) {
    throw "SIGFAIL:$Id"
}

function Get-SigId($ErrorRecord) {
    $message = $ErrorRecord.Exception.Message
    if ($message -like "SIGFAIL:*") {
        return $message.Substring(8)
    }
    return $null
}

function Format-Unsupported([string]$Id) {
    if (-not $Id) { $Id = "unknown" }
    return "This Garry's Mod build isn't supported (signature $Id not found or ambiguous)"
}

function Join-Game([string]$Game, [string]$Relative) {
    $full = $Game
    foreach ($part in ($Relative -split '[\\/]' | Where-Object { $_ })) {
        $full = Join-Path $full $part
    }
    return $full
}

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-Sha256Bytes([byte[]]$Data) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Data)).Replace("-", "").ToLowerInvariant())
    } finally {
        $sha.Dispose()
    }
}

function Format-Offset([int64]$Value) {
    return ("0x{0:x}" -f $Value)
}

function Format-Bytes([byte[]]$Bytes) {
    $builder = New-Object System.Text.StringBuilder
    foreach ($byte in $Bytes) {
        [void]$builder.Append($byte.ToString("x2"))
    }
    return $builder.ToString()
}

function Write-Lines($Lines) {
    foreach ($line in @($Lines)) {
        if ($null -ne $line -and "$line" -ne "") {
            [Console]::Out.WriteLine([string]$line)
        }
    }
}

function Parse-Sig([string]$Text) {
    $raw = $Text.Replace("[", " [ ").Replace("]", " ] ")
    $pat = New-Object System.Collections.Generic.List[int]
    $site = -1
    $end = -1
    foreach ($token in ($raw -split "\s+")) {
        if (-not $token) { continue }
        if ($token -eq "[") { $site = $pat.Count }
        elseif ($token -eq "]") { $end = $pat.Count }
        elseif ($token -eq "??") { $pat.Add(-1) }
        else { $pat.Add([Convert]::ToInt32($token, 16)) }
    }
    if ($site -lt 0) {
        $site = 0
        $end = $pat.Count
    }
    return @{ Pat = $pat.ToArray(); Site = [int]$site; Size = [int]($end - $site) }
}

function Find-Pattern([byte[]]$Data, [int[]]$Pat, [string]$Id) {
    try {
        $hits = [StickyBlood.SigScan]::FindAll($Data, $Pat)
    } catch {
        Throw-Sig $Id
    }
    return ,$hits
}

function Find-Unique([byte[]]$Data, [string]$Signature, [string]$Id) {
    $parsed = Parse-Sig $Signature
    $hits = Find-Pattern $Data $parsed.Pat $Id
    if ($hits.Length -ne 1) { Throw-Sig $Id }
    return @{ At = [int]($hits[0] + $parsed.Site); Parsed = $parsed }
}

function Get-ReplacePattern([string]$Text) {
    $list = New-Object System.Collections.Generic.List[int]
    foreach ($match in [regex]::Matches($Text, "\{[^}]+\}|\S+")) {
        $token = $match.Value
        if ($token.StartsWith("{rel32:")) {
            $list.Add(-1); $list.Add(-1); $list.Add(-1); $list.Add(-1)
        } elseif ($token -eq "{keep}") {
            $list.Add(-1)
        } else {
            $list.Add([Convert]::ToInt32($token, 16))
        }
    }
    return ,$list.ToArray()
}

function Resolve-Replace([string]$Text, [int]$At, [byte[]]$Orig, $Labels, [string]$PatchId) {
    $out = New-Object System.Collections.Generic.List[byte]
    foreach ($match in [regex]::Matches($Text, "\{[^}]+\}|\S+")) {
        $token = $match.Value
        if ($token.StartsWith("{rel32:") -and $token.EndsWith("}")) {
            $name = $token.Substring(7, $token.Length - 8)
            if ($name -eq "@jcc32") {
                $disp = [BitConverter]::ToInt32($Orig, 2)
                $target = [int64]$At + 6 + $disp
            } else {
                $parsed = [regex]::Match($name, "^([\w]+)([+-]\d+)?$")
                if (-not $parsed.Success -or -not $Labels.ContainsKey($parsed.Groups[1].Value)) {
                    Throw-Sig $PatchId
                }
                $target = [int64]$Labels[$parsed.Groups[1].Value]
                if ($parsed.Groups[2].Success) {
                    $target += [int64]$parsed.Groups[2].Value
                }
            }
            $relative = $target - ([int64]$At + [int64]$out.Count + 4)
            if ($relative -lt -2147483648 -or $relative -gt 2147483647) { Throw-Sig $PatchId }
            foreach ($byte in [BitConverter]::GetBytes([int32]$relative)) {
                $out.Add($byte)
            }
        } elseif ($token -eq "{keep}") {
            $out.Add($Orig[$out.Count])
        } else {
            $out.Add([byte][Convert]::ToInt32($token, 16))
        }
    }
    return ,$out.ToArray()
}

function Get-TextRange([byte[]]$Data) {
    try {
        if ($Data.Length -lt 64) { Throw-Sig "unknown" }
        $pe = [BitConverter]::ToInt32($Data, 0x3C)
        if ($pe -lt 0 -or ($pe + 24) -gt $Data.Length) { Throw-Sig "unknown" }
        $sections = [BitConverter]::ToUInt16($Data, $pe + 6)
        $optional = [BitConverter]::ToUInt16($Data, $pe + 20)
        $header = $pe + 24 + $optional
        for ($index = 0; $index -lt $sections; $index++) {
            $off = $header + (40 * $index)
            if (($off + 24) -gt $Data.Length) { Throw-Sig "unknown" }
            $nameBytes = New-Object byte[] 8
            [Array]::Copy($Data, $off, $nameBytes, 0, 8)
            $name = [Text.Encoding]::ASCII.GetString($nameBytes).TrimEnd([char]0)
            if ($name -eq ".text") {
                $rawSize = [int64][BitConverter]::ToUInt32($Data, $off + 16)
                $raw = [int64][BitConverter]::ToUInt32($Data, $off + 20)
                return @{ Low = [int]$raw; High = [int]($raw + $rawSize) }
            }
        }
    } catch {
        if (Get-SigId $_) { throw }
        Throw-Sig "unknown"
    }
    Throw-Sig "unknown"
}

function Test-Literals([int[]]$Pat, [int]$Start, [int[]]$Expect) {
    $found = 0
    for ($i = 0; $i -lt $Expect.Length; $i++) {
        $want = $Expect[$i]
        if ($want -lt 0) { continue }
        $have = $Pat[$Start + $i]
        if ($have -lt 0 -or $have -ne $want) { return $false }
        $found++
    }
    return ($found -ge 4)
}

function Test-Edge([int[]]$Pat, [int]$Start, [int[]]$Expect, [int]$ExpectStart, [int]$Length) {
    if ($Length -le 0) { return $false }
    for ($i = 0; $i -lt $Length; $i++) {
        $want = $Expect[$ExpectStart + $i]
        $have = $Pat[$Start + $i]
        if ($want -lt 0 -or $have -lt 0 -or $have -ne $want) { return $false }
    }
    return $true
}

function New-PatchedPattern($Patch, $Patches) {
    $parsed = Parse-Sig $Patch.sig
    $replacement = Get-ReplacePattern $Patch.replace
    if ($replacement.Length -ne $parsed.Size) { Throw-Sig $Patch.id }
    $list = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $parsed.Site; $i++) { $list.Add([int]$parsed.Pat[$i]) }
    foreach ($byte in $replacement) { $list.Add([int]$byte) }
    for ($i = $parsed.Site + $parsed.Size; $i -lt $parsed.Pat.Length; $i++) { $list.Add([int]$parsed.Pat[$i]) }
    $arr = $list.ToArray()
    $site = [int]$parsed.Site
    $size = [int]$parsed.Size
    foreach ($other in @($Patches)) {
        if ($other.id -eq $Patch.id) { continue }
        $expect = (Parse-Sig $other.expect).Pat
        for ($i = 0; $i -le ($arr.Length - $expect.Length); $i++) {
            $end = $i + $expect.Length
            if ($end -le $site -or $i -ge ($site + $size)) {
                if (Test-Literals $arr $i $expect) {
                    for ($k = 0; $k -lt $expect.Length; $k++) { $arr[$i + $k] = -1 }
                }
            }
        }
        $limit = $arr.Length - ($site + $size)
        $best = 0
        $maxSuffix = [Math]::Min($limit, $expect.Length)
        for ($n = 1; $n -le $maxSuffix; $n++) {
            if (Test-Edge $arr ($arr.Length - $n) $expect 0 $n) { $best = $n }
        }
        for ($k = 0; $k -lt $best; $k++) { $arr[$arr.Length - 1 - $k] = -1 }
        $best = 0
        $maxPrefix = [Math]::Min($site, $expect.Length)
        for ($n = 1; $n -le $maxPrefix; $n++) {
            if (Test-Edge $arr 0 $expect ($expect.Length - $n) $n) { $best = $n }
        }
        for ($k = 0; $k -lt $best; $k++) { $arr[$k] = -1 }
    }
    return @{ Pat = $arr; Site = $site }
}

function Test-Prologue([byte[]]$Data, [int]$At, $Required, [string]$Id) {
    if (-not $Required) { return }
    $prologue = (Parse-Sig $Required.sig).Pat
    $start = $At - [int]$Required.distance
    if ($start -lt 0 -or ($start + $prologue.Length) -gt $Data.Length) { Throw-Sig $Id }
    for ($index = 0; $index -lt $prologue.Length; $index++) {
        if ($prologue[$index] -ge 0 -and $Data[$start + $index] -ne [byte]$prologue[$index]) {
            Throw-Sig $Id
        }
    }
}

function Plan-File([byte[]]$Data, $Spec) {
    $range = Get-TextRange $Data
    $labels = @{}
    $anchors = @()
    if ($Spec.anchors) { $anchors = @($Spec.anchors) }
    foreach ($anchor in $anchors) {
        $found = Find-Unique $Data $anchor.sig $anchor.id
        $labels[$anchor.id] = [int]$found.At
    }
    $sites = New-Object System.Collections.Generic.List[object]
    foreach ($patch in @($Spec.patches)) {
        $found = Find-Unique $Data $patch.sig $patch.id
        $labels[$patch.id] = [int]$found.At
        $sites.Add(@{ Patch = $patch; At = [int]$found.At })
    }
    foreach ($name in @($labels.Keys)) {
        $offset = [int]$labels[$name]
        if (-not ($offset -ge $range.Low -and $offset -lt $range.High)) { Throw-Sig $name }
    }
    $edits = New-Object System.Collections.Generic.List[object]
    foreach ($site in $sites) {
        $patch = $site.Patch
        $at = [int]$site.At
        $expect = (Parse-Sig $patch.expect).Pat
        $bracket = Parse-Sig $patch.sig
        if ($expect.Length -ne $bracket.Size) { Throw-Sig $patch.id }
        $original = New-Object byte[] $expect.Length
        [Array]::Copy($Data, $at, $original, 0, $expect.Length)
        for ($index = 0; $index -lt $expect.Length; $index++) {
            if ($expect[$index] -ge 0 -and $original[$index] -ne [byte]$expect[$index]) {
                Throw-Sig $patch.id
            }
        }
        $replacement = Resolve-Replace $patch.replace $at $original $labels $patch.id
        if ($replacement.Length -ne $expect.Length) { Throw-Sig $patch.id }
        Test-Prologue $Data $at $patch.require_before $patch.id
        $edits.Add(@{ Id = [string]$patch.id; At = $at; Orig = $original; Repl = $replacement })
    }
    $sorted = @($edits | Sort-Object { $_.At }, { $_.Id })
    for ($index = 0; $index -lt ($sorted.Count - 1); $index++) {
        $left = $sorted[$index]
        $right = $sorted[$index + 1]
        if (($left.At + $left.Orig.Length) -gt $right.At) { Throw-Sig $left.Id }
    }
    return @{ Edits = $sorted; Labels = $labels }
}

function Test-Patched([byte[]]$Data, $Spec) {
    $range = Get-TextRange $Data
    $anchors = @()
    if ($Spec.anchors) { $anchors = @($Spec.anchors) }
    foreach ($anchor in $anchors) {
        $found = Find-Unique $Data $anchor.sig $anchor.id
        if (-not ($found.At -ge $range.Low -and $found.At -lt $range.High)) { Throw-Sig $anchor.id }
    }
    foreach ($patch in @($Spec.patches)) {
        $built = New-PatchedPattern $patch $Spec.patches
        $hits = Find-Pattern $Data $built.Pat $patch.id
        if ($hits.Length -ne 1) { Throw-Sig $patch.id }
        $at = [int]($hits[0] + $built.Site)
        if (-not ($at -ge $range.Low -and $at -lt $range.High)) { Throw-Sig $patch.id }
        Test-Prologue $Data $at $patch.require_before $patch.id
    }
}

function Classify-Bytes([byte[]]$Data, $Spec) {
    $firstId = "unknown"
    try {
        $plan = Plan-File $Data $Spec
        return @{ State = "pristine"; Edits = $plan.Edits; Labels = $plan.Labels }
    } catch {
        $parsed = Get-SigId $_
        if ($parsed) { $firstId = $parsed }
        elseif ($_.Exception.Message -like "SIGFAIL:*") { $firstId = "unknown" }
        else {
            $inner = Get-SigId $_
            if (-not $inner) { throw }
        }
    }
    try {
        Test-Patched $Data $Spec
        return @{ State = "patched"; Edits = @(); Labels = @{} }
    } catch {
        $again = Get-SigId $_
        if (-not $again -and $_.Exception.Message -notlike "SIGFAIL:*") { throw }
    }
    throw (Format-Unsupported $firstId)
}

function Test-Sites([byte[]]$Original, [byte[]]$Patched, $Edits) {
    if ($Original.Length -ne $Patched.Length) { return $false }
    $copy = New-Object byte[] $Patched.Length
    [Array]::Copy($Patched, $copy, $Patched.Length)
    foreach ($edit in @($Edits)) {
        $repl = [byte[]]$edit.Repl
        $orig = [byte[]]$edit.Orig
        for ($i = 0; $i -lt $repl.Length; $i++) {
            if ($Patched[$edit.At + $i] -ne $repl[$i]) { return $false }
        }
        [Array]::Copy($orig, 0, $copy, [int]$edit.At, $orig.Length)
    }
    return (Get-Sha256Bytes $copy) -eq (Get-Sha256Bytes $Original)
}

function Apply-Edits([byte[]]$Data, $Edits) {
    $output = New-Object byte[] $Data.Length
    [Array]::Copy($Data, $output, $Data.Length)
    foreach ($edit in @($Edits)) {
        $orig = [byte[]]$edit.Orig
        $repl = [byte[]]$edit.Repl
        for ($i = 0; $i -lt $orig.Length; $i++) {
            if ($output[$edit.At + $i] -ne $orig[$i]) { throw "edit slipped" }
        }
        [Array]::Copy($repl, 0, $output, [int]$edit.At, $repl.Length)
    }
    return ,$output
}

function Get-PlanLines([string]$Name, [string]$Digest, $Spec, [string]$State, $Edits) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("FILE $Name")
    if ($State -eq "patched") {
        $lines.Add("patched")
        return ,$lines.ToArray()
    }
    $known = $false
    if ($Spec.known_pristine_sha256) {
        foreach ($hash in @($Spec.known_pristine_sha256)) {
            if ($Digest -eq [string]$hash) { $known = $true }
        }
    }
    if ($known) { $lines.Add("known build") } else { $lines.Add("unknown build, signatures OK") }
    foreach ($edit in @($Edits)) {
        $lines.Add(("{0} {1} {2} -> {3}" -f $edit.Id, (Format-Offset $edit.At), (Format-Bytes $edit.Orig), (Format-Bytes $edit.Repl)))
    }
    return ,$lines.ToArray()
}

function Read-V1Index {
    $map = @{}
    if (-not (Test-Path -LiteralPath $V1Path)) { return $map }
    $manifest = Get-Content -LiteralPath $V1Path -Raw | ConvertFrom-Json
    foreach ($spec in @($manifest.files)) {
        $name = [IO.Path]::GetFileName(($spec.path -replace "\\", "/"))
        $map[$name] = $spec
    }
    return $map
}

function Normalize-Game([string]$Path) {
    $full = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
    if (Test-Path -LiteralPath (Join-Game $full "gameinfo.txt")) {
        $full = Split-Path -Parent $full
    }
    if (-not (Test-Path -LiteralPath (Join-Game $full "garrysmod/gameinfo.txt"))) {
        throw "Not a Garry's Mod folder: $full"
    }
    return $full
}

function Find-Game([string]$Requested) {
    if ($Requested) { return (Normalize-Game $Requested) }
    $steamRoots = New-Object System.Collections.Generic.List[string]
    try {
        $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
        if ($steamPath) { $steamRoots.Add($steamPath) }
    } catch {}
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    if ($programFilesX86) { $steamRoots.Add((Join-Path $programFilesX86 "Steam")) }
    if ($env:ProgramFiles) { $steamRoots.Add((Join-Path $env:ProgramFiles "Steam")) }
    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steam in $steamRoots) {
        if (-not $steam -or -not (Test-Path -LiteralPath $steam)) { continue }
        $libraries.Add($steam)
        $vdf = Join-Path $steam "steamapps/libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '^\s*"path"\s+"([^"]+)"') {
                    $libraries.Add($matches[1].Replace("\\", "\"))
                }
            }
        }
    }
    foreach ($library in $libraries) {
        $candidate = Join-Game $library "steamapps/common/GarrysMod"
        if (Test-Path -LiteralPath (Join-Game $candidate "garrysmod/gameinfo.txt")) {
            return (Normalize-Game $candidate)
        }
    }
    throw "Could not find Garry's Mod. Pass -GamePath 'C:\...\GarrysMod'."
}

function Assert-Binaries($Game, $Manifest) {
    $win64 = Join-Game $Game "bin/win64"
    if (-not (Test-Path -LiteralPath $win64)) { throw $Script:BranchRequired }
    foreach ($spec in @($Manifest.files)) {
        $target = Join-Game $Game $spec.path
        if (-not (Test-Path -LiteralPath $target)) { throw $Script:BranchRequired }
    }
}

function Write-Atomic([string]$Target, [byte[]]$Data, [byte[]]$Original, $Edits) {
    $temp = Join-Path (Split-Path -Parent $Target) (".stickyblood.$PID.$([guid]::NewGuid().ToString('N')).tmp")
    try {
        [IO.File]::WriteAllBytes($temp, $Data)
        $readback = [IO.File]::ReadAllBytes($temp)
        if ((Get-Sha256Bytes $readback) -ne (Get-Sha256Bytes $Data)) {
            throw "Generated file failed verification: $Target"
        }
        if ($null -ne $Edits) {
            if (-not (Test-Sites $Original $readback $Edits)) {
                throw "Generated file failed verification: $Target"
            }
        }
        Move-Item -LiteralPath $temp -Destination $Target -Force
        $temp = $null
    } finally {
        if ($temp -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

function Copy-Atomic([string]$Source, [string]$Destination) {
    $temp = Join-Path (Split-Path -Parent $Destination) (".stickyblood.$PID.$([guid]::NewGuid().ToString('N')).tmp")
    try {
        Copy-Item -LiteralPath $Source -Destination $temp -Force
        Move-Item -LiteralPath $temp -Destination $Destination -Force
        $temp = $null
    } finally {
        if ($temp -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

function Get-BackupPath([string]$Target, $Spec) {
    return (Join-Path (Split-Path -Parent $Target) ([string]$Spec.backup))
}

function Get-SidecarPath([string]$Target) {
    $name = Split-Path -Leaf $Target
    return (Join-Path (Split-Path -Parent $Target) ($name + ".stickyblood.json"))
}

function Read-Sidecar([string]$Target) {
    $path = Get-SidecarPath $Target
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Write-Sidecar([string]$Target, [string]$Pristine, [string]$Patched, [string]$Version, $Labels) {
    $names = @($Labels.Keys | Sort-Object)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("{")
    $lines.Add('  "offsets": {')
    for ($i = 0; $i -lt $names.Count; $i++) {
        $comma = ""
        if ($i -lt ($names.Count - 1)) { $comma = "," }
        $key = [string]$names[$i]
        $value = Format-Offset ([int64]$Labels[$key])
        $lines.Add(('    "{0}": "{1}"{2}' -f $key, $value, $comma))
    }
    $lines.Add("  },")
    $lines.Add(('  "patched_sha256": "{0}",' -f $Patched))
    $lines.Add(('  "pristine_sha256": "{0}",' -f $Pristine))
    $lines.Add(('  "version": "{0}"' -f $Version))
    $lines.Add("}")
    $lines.Add("")
    $text = [string]::Join("`n", $lines.ToArray())
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $bytes = $utf8.GetBytes($text)
    Write-Atomic (Get-SidecarPath $Target) $bytes $null $null
}

function Get-V1Candidates([string]$Target, $V1) {
    $dir = Split-Path -Parent $Target
    $name = Split-Path -Leaf $Target
    $list = New-Object System.Collections.Generic.List[string]
    if ($V1) { $list.Add((Join-Path $dir ([string]$V1.backup))) }
    $legacy = Join-Path $dir ($name + ".bak")
    if (-not $list.Contains($legacy)) { $list.Add($legacy) }
    return $list
}

function Find-V1Backup([string]$Target, $V1, [string]$ExpectedHash) {
    if (-not $V1) { return $null }
    if ($ExpectedHash -ne [string]$V1.pristine_sha256) { return $null }
    foreach ($candidate in (Get-V1Candidates $Target $V1)) {
        if ((Test-Path -LiteralPath $candidate) -and (Get-Sha256File $candidate) -eq [string]$V1.pristine_sha256) {
            return $candidate
        }
    }
    return $null
}

function Ensure-Backup([string]$Target, $Spec, [string]$CurrentHash, $V1) {
    $backup = Get-BackupPath $Target $Spec
    if (Test-Path -LiteralPath $backup) {
        if ((Get-Sha256File $backup) -ne $CurrentHash) {
            $stamp = [DateTime]::UtcNow.ToString("yyyyMMddHHmmss")
            $leaf = Split-Path -Leaf $Target
            $stamped = Join-Path (Split-Path -Parent $Target) ($leaf + ".stickyblood." + $stamp + ".bak")
            $counter = 1
            while (Test-Path -LiteralPath $stamped) {
                $stamped = Join-Path (Split-Path -Parent $Target) ($leaf + ".stickyblood." + $stamp + "-" + $counter + ".bak")
                $counter++
            }
            Move-Item -LiteralPath $backup -Destination $stamped
            Copy-Atomic $Target $backup
        }
    } else {
        $adopted = $null
        if ($V1 -and $CurrentHash -eq [string]$V1.pristine_sha256) {
            $adopted = Find-V1Backup $Target $V1 ([string]$V1.pristine_sha256)
        }
        if ($adopted) { Copy-Atomic $adopted $backup }
        else { Copy-Atomic $Target $backup }
    }
    if ((Get-Sha256File $backup) -ne $CurrentHash) {
        throw "Backup does not match the game file: $backup"
    }
    return $backup
}

function Get-Prepared($Game, $Manifest, [switch]$Lenient) {
    Assert-Binaries $Game $Manifest
    $prepared = New-Object System.Collections.Generic.List[object]
    foreach ($spec in @($Manifest.files)) {
        $target = Join-Game $Game $spec.path
        $data = [IO.File]::ReadAllBytes($target)
        $state = $null
        $edits = @()
        $labels = @{}
        $errorText = $null
        try {
            $classified = Classify-Bytes $data $spec
            $state = [string]$classified.State
            $edits = $classified.Edits
            $labels = $classified.Labels
        } catch {
            $message = $_.Exception.Message
            if ($message -like "SIGFAIL:*") { $message = Format-Unsupported $message.Substring(8) }
            if (-not $Lenient -or $message -notlike "*isn't supported*") { throw }
            $state = "unsupported"
            $errorText = $message
        }
        $prepared.Add(@{
            Spec = $spec
            Target = $target
            Data = $data
            Digest = (Get-Sha256Bytes $data)
            State = $state
            Edits = $edits
            Labels = $labels
            Error = $errorText
        })
    }
    return $prepared
}

function Get-RenderLines([string]$Game, $Prepared) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Game: $Game")
    foreach ($item in @($Prepared)) {
        $plan = Get-PlanLines (Split-Path -Leaf $item.Target) $item.Digest $item.Spec $item.State $item.Edits
        foreach ($line in @($plan)) { $lines.Add([string]$line) }
    }
    return ,$lines.ToArray()
}

function Install-Addon([string]$Game) {
    $destination = Join-Game $Game "garrysmod/addons/sticky_blood"
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root "addon.json") -Destination (Join-Path $destination "addon.json")
    Copy-Item -LiteralPath (Join-Path $Root "lua") -Destination $destination -Recurse
    [Console]::Out.WriteLine("Installed addon: $destination")
}

function Remove-Addon([string]$Game) {
    $destination = Join-Game $Game "garrysmod/addons/sticky_blood"
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
        [Console]::Out.WriteLine("Removed addon: $destination")
    }
}

function Install-Game([string]$Game, $Manifest, $V1Index) {
    $prepared = Get-Prepared $Game $Manifest
    if ($DryRun) {
        Write-Lines (Get-RenderLines $Game $prepared)
        return
    }
    foreach ($item in @($prepared)) {
        Write-Lines (Get-PlanLines (Split-Path -Leaf $item.Target) $item.Digest $item.Spec $item.State $item.Edits)
        if ($item.State -eq "patched") {
            [Console]::Out.WriteLine("Already patched: $((Split-Path -Leaf $item.Target))")
            continue
        }
        $name = Split-Path -Leaf $item.Target
        $v1 = $null
        if ($V1Index.ContainsKey($name)) { $v1 = $V1Index[$name] }
        Ensure-Backup $item.Target $item.Spec $item.Digest $v1
        $patched = Apply-Edits $item.Data $item.Edits
        if (-not (Test-Sites $item.Data $patched $item.Edits)) {
            throw "Generated file failed verification: $($item.Target)"
        }
        $patchedHash = Get-Sha256Bytes $patched
        Write-Sidecar $item.Target $item.Digest $patchedHash ([string]$Manifest.version) $item.Labels
        try {
            Write-Atomic $item.Target $patched $item.Data $item.Edits
        } catch {
            $sidecar = Get-SidecarPath $item.Target
            if (Test-Path -LiteralPath $sidecar) { Remove-Item -LiteralPath $sidecar -Force }
            throw
        }
        [Console]::Out.WriteLine("Patched: $($item.Target)")
    }
    Install-Addon $Game
}

function Decide-Uninstall($Item, $V1) {
    $target = [string]$Item.Target
    $current = [string]$Item.Digest
    $sidecar = Read-Sidecar $target
    $backup = Get-BackupPath $target $Item.Spec
    if ($sidecar -and $current -eq [string]$sidecar.pristine_sha256) {
        return @{ Action = "restored"; Target = $target }
    }
    if ($sidecar -and $current -eq [string]$sidecar.patched_sha256 -and (Test-Path -LiteralPath $backup) -and (Get-Sha256File $backup) -eq [string]$sidecar.pristine_sha256) {
        return @{
            Action = "restore"
            Target = $target
            Source = $backup
            Expected = [string]$sidecar.pristine_sha256
            Delete = @($backup, (Get-SidecarPath $target))
        }
    }
    if ($V1 -and $current -eq [string]$V1.patched_sha256) {
        $source = Find-V1Backup $target $V1 ([string]$V1.pristine_sha256)
        if ($source) {
            $delete = New-Object System.Collections.Generic.List[string]
            if ($source.EndsWith(".stickyblood-v1.bak")) { $delete.Add($source) }
            $side = Get-SidecarPath $target
            if (Test-Path -LiteralPath $side) { $delete.Add($side) }
            return @{
                Action = "restore"
                Target = $target
                Source = $source
                Expected = [string]$V1.pristine_sha256
                Delete = $delete.ToArray()
            }
        }
    }
    if ($Item.State -eq "pristine" -and $sidecar) {
        $delete = New-Object System.Collections.Generic.List[string]
        $delete.Add((Get-SidecarPath $target))
        if (Test-Path -LiteralPath $backup) { $delete.Add($backup) }
        return @{ Action = "stale"; Target = $target; Delete = $delete.ToArray() }
    }
    if ($Item.State -eq "pristine" -and -not $sidecar) {
        return @{ Action = "restored"; Target = $target }
    }
    throw $Script:SteamVerify
}

function Uninstall-Game([string]$Game, $Manifest, $V1Index) {
    $prepared = Get-Prepared $Game $Manifest -Lenient
    if ($DryRun) {
        foreach ($item in @($prepared)) {
            if ($item.State -eq "unsupported") { throw [string]$item.Error }
        }
        Write-Lines (Get-RenderLines $Game $prepared)
        return
    }
    $decisions = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($prepared)) {
        $name = Split-Path -Leaf $item.Target
        $v1 = $null
        if ($V1Index.ContainsKey($name)) { $v1 = $V1Index[$name] }
        $decisions.Add((Decide-Uninstall $item $v1))
    }
    foreach ($decision in $decisions) {
        $target = [string]$decision.Target
        if ($decision.Action -eq "restored") {
            [Console]::Out.WriteLine("Already restored: $((Split-Path -Leaf $target))")
            continue
        }
        if ($decision.Action -eq "stale") {
            foreach ($path in @($decision.Delete)) {
                if ($path -and (Test-Path -LiteralPath $path)) {
                    Remove-Item -LiteralPath $path -Force
                    [Console]::Out.WriteLine("Removed stale backup: $((Split-Path -Leaf $path))")
                }
            }
            continue
        }
        $data = [IO.File]::ReadAllBytes([string]$decision.Source)
        Write-Atomic $target $data $null $null
        if ((Get-Sha256File $target) -ne [string]$decision.Expected) {
            throw "Generated file failed verification: $target"
        }
        foreach ($path in @($decision.Delete)) {
            if ($path -and $path -ne $target -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Force
            }
        }
        [Console]::Out.WriteLine("Restored: $target")
    }
    Remove-Addon $Game
}

try {
    if (-not $SkipRunningCheck) {
        if (Get-Process -Name "gmod" -ErrorAction SilentlyContinue) {
            throw "Garry's Mod is running. Fully quit it before continuing."
        }
    }
    $game = Find-Game $GamePath
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if ([int]$manifest.format -ne 2) { throw "Unsupported patch manifest format" }
    $v1Index = Read-V1Index
    if (-not $DryRun) { [Console]::Out.WriteLine("Game: $game") }
    if ($Action -eq "install") {
        Install-Game $game $manifest $v1Index
    } else {
        Uninstall-Game $game $manifest $v1Index
    }
    if (-not $DryRun) { [Console]::Out.WriteLine("Done. Fully restart Garry's Mod.") }
    exit 0
} catch {
    $message = $_.Exception.Message
    if (-not $message) { $message = "$_" }
    if ($message -like "SIGFAIL:*") { $message = Format-Unsupported $message.Substring(8) }
    [Console]::Error.WriteLine("Error: $message")
    exit 1
}
