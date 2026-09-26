# Install the same universal source on a local FiveM or RedM server.
param(
    [Parameter(Mandatory=$true)][string]$ServerBase,
    [string]$Category = '[standalone]'
)
$ErrorActionPreference = 'Stop'

function Assert-SafeChildPath {
    param([string]$Path, [string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $fullPath.StartsWith($fullRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing path outside $fullRoot`: $fullPath"
    }
    # Refuse links/junctions below the explicitly selected server directory so
    # lexical containment cannot redirect a recursive copy or directory move.
    $current = $fullPath
    while (-not $current.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked path: $current" }
        }
        $current = [IO.Path]::GetDirectoryName($current)
        if (-not $current) { throw "Cannot validate path: $fullPath" }
    }
    return $fullPath
}

function Get-UpdatedConfig {
    param([string]$Text, [string]$Version)
    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [regex]::Split($Text, '(?<=\n)')
    $builder = [Text.StringBuilder]::new()
    $hasAce = $false
    $hasStart = $false
    foreach ($line in $lines) {
        $body = $line.TrimEnd("`r", "`n")
        $ending = $line.Substring($body.Length)
        if ($body -match '^\s*add_ace\s+group\.admin\s+(?:frontier_camera|arbat16_camera)\.use\s+allow\s*$') {
            if (-not $hasAce) {
                [void]$builder.Append('add_ace group.admin arbat16_camera.use allow').Append($ending)
                $hasAce = $true
            }
        } elseif ($body -match '^\s*(?:ensure|start)\s+(?:frontier_camera|arbat16_camera)\s*$') {
            if (-not $hasStart) {
                [void]$builder.Append('ensure arbat16_camera').Append($ending)
                $hasStart = $true
            }
        } else {
            $updatedBody = [regex]::Replace($body, '(?i)^(\s*#\s*)Frontier Camera\b.*$', "`${1}Arbat16 Camera v$Version")
            [void]$builder.Append($updatedBody).Append($ending)
        }
    }
    if (-not $hasAce -or -not $hasStart) {
        if ($builder.Length -gt 0 -and -not $builder.ToString().EndsWith("`n")) { [void]$builder.Append($newline) }
        [void]$builder.Append("# Arbat16 Camera v$Version").Append($newline)
        if (-not $hasAce) { [void]$builder.Append('add_ace group.admin arbat16_camera.use allow').Append($newline) }
        if (-not $hasStart) { [void]$builder.Append('ensure arbat16_camera').Append($newline) }
    }
    return $builder.ToString()
}

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\resource\arbat16_camera'))
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'fxmanifest.lua') -PathType Leaf)) { throw 'Source manifest missing.' }
foreach ($sourceItem in Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force) {
    if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked source: $($sourceItem.FullName)" }
}
$serverRoot = [IO.Path]::GetFullPath($ServerBase)
if (-not (Test-Path -LiteralPath $serverRoot -PathType Container)) { throw "Server directory does not exist: $serverRoot" }
if ($Category -notmatch '^\[[A-Za-z0-9_-]+\]$') { throw 'Use a single bracketed resource category.' }
$resourceParent = Assert-SafeChildPath (Join-Path (Join-Path $serverRoot 'resources') $Category) $serverRoot
if (-not (Test-Path -LiteralPath $resourceParent -PathType Container)) { [IO.Directory]::CreateDirectory($resourceParent) | Out-Null }
$deployTarget = Assert-SafeChildPath (Join-Path $resourceParent 'arbat16_camera') $resourceParent
$legacyTarget = Assert-SafeChildPath (Join-Path $resourceParent 'frontier_camera') $resourceParent
foreach ($resourcePath in @($deployTarget, $legacyTarget)) {
    if ((Test-Path -LiteralPath $resourcePath) -and -not (Test-Path -LiteralPath $resourcePath -PathType Container)) { throw "Resource path is not a directory: $resourcePath" }
}
$backupRoot = Assert-SafeChildPath (Join-Path $serverRoot 'backups\arbat16_camera') $serverRoot
$configFile = Assert-SafeChildPath (Join-Path $serverRoot 'server.cfg') $serverRoot
if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) { throw 'server.cfg missing; installation aborted.' }
$manifestText = [IO.File]::ReadAllText((Join-Path $sourceRoot 'fxmanifest.lua'))
$versionMatch = [regex]::Match($manifestText, "(?m)^version\s+'([0-9]+\.[0-9]+\.[0-9]+)'")
if (-not $versionMatch.Success) { throw 'Manifest requires a semantic version.' }
$releaseVersion = $versionMatch.Groups[1].Value
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$stagedInstall = Assert-SafeChildPath (Join-Path $backupRoot "staging-v$releaseVersion-$stamp") $backupRoot
$priorDirectory = Assert-SafeChildPath (Join-Path $backupRoot "arbat16_camera-installed-before-$stamp") $backupRoot
$legacyDirectory = Assert-SafeChildPath (Join-Path $backupRoot "frontier_camera-installed-before-$stamp") $backupRoot
$failedDirectory = Assert-SafeChildPath (Join-Path $backupRoot "arbat16_camera-failed-install-$stamp") $backupRoot
$priorArchivePath = Assert-SafeChildPath (Join-Path $backupRoot "arbat16_camera-before-$stamp.zip") $backupRoot
$legacyArchivePath = Assert-SafeChildPath (Join-Path $backupRoot "frontier_camera-before-$stamp.zip") $backupRoot
$releaseArchive = Assert-SafeChildPath (Join-Path $backupRoot "arbat16_camera-v$releaseVersion-$stamp.zip") $backupRoot
$configBackupPath = Assert-SafeChildPath (Join-Path $backupRoot "server.cfg-before-$stamp.bak") $backupRoot
$receiptPath = Assert-SafeChildPath (Join-Path $backupRoot "release-v$releaseVersion-$stamp.json") $backupRoot
foreach ($newPath in @($stagedInstall, $priorDirectory, $legacyDirectory, $failedDirectory, $priorArchivePath, $legacyArchivePath, $releaseArchive, $configBackupPath, $receiptPath)) {
    if (Test-Path -LiteralPath $newPath) { throw "Refusing to reuse backup path: $newPath" }
}

$configText = [IO.File]::ReadAllText($configFile)
$updatedConfig = Get-UpdatedConfig $configText $releaseVersion
$configChanged = $updatedConfig -cne $configText
$configBackup = $null
if ($configChanged) {
    Copy-Item -LiteralPath $configFile -Destination $configBackupPath
    $configBackup = $configBackupPath
}
$priorArchive = $null
$legacyArchive = $null
if (Test-Path -LiteralPath $deployTarget) {
    Compress-Archive -LiteralPath $deployTarget -DestinationPath $priorArchivePath -CompressionLevel Optimal
    $priorArchive = $priorArchivePath
}
if (Test-Path -LiteralPath $legacyTarget) {
    Compress-Archive -LiteralPath $legacyTarget -DestinationPath $legacyArchivePath -CompressionLevel Optimal
    $legacyArchive = $legacyArchivePath
}
Compress-Archive -LiteralPath $sourceRoot -DestinationPath $releaseArchive -CompressionLevel Optimal
[IO.Directory]::CreateDirectory($stagedInstall) | Out-Null
foreach ($sourceItem in Get-ChildItem -LiteralPath $sourceRoot -Force) {
    Copy-Item -LiteralPath $sourceItem.FullName -Destination $stagedInstall -Recurse -Force
}
$verifiedFiles = @()
foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force) {
    $relativeFile = [IO.Path]::GetRelativePath($sourceRoot, $sourceFile.FullName)
    $targetFile = Assert-SafeChildPath (Join-Path $stagedInstall $relativeFile) $stagedInstall
    $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash -ne $sourceHash) { throw "Copy verification failed: $relativeFile" }
    $verifiedFiles += [ordered]@{path=$relativeFile;sha256=$sourceHash}
}

# Move only fully validated paths. Both old names retain their directories and
# ZIPs outside resources, preventing duplicate discovery after refresh.
$movedPrevious = $false
$movedLegacy = $false
$installedNew = $false
$configWriteAttempted = $false
try {
    if (Test-Path -LiteralPath $deployTarget) {
        Move-Item -LiteralPath $deployTarget -Destination $priorDirectory
        $movedPrevious = $true
    }
    if (Test-Path -LiteralPath $legacyTarget) {
        Move-Item -LiteralPath $legacyTarget -Destination $legacyDirectory
        $movedLegacy = $true
    }
    Move-Item -LiteralPath $stagedInstall -Destination $deployTarget
    $installedNew = $true
    if ($configChanged) {
        $configWriteAttempted = $true
        [IO.File]::WriteAllText($configFile, $updatedConfig, [Text.UTF8Encoding]::new($false))
    }
} catch {
    $installFailure = $_
    if ($configWriteAttempted) { Copy-Item -LiteralPath $configBackup -Destination $configFile -Force }
    if ($installedNew -and (Test-Path -LiteralPath $deployTarget)) { Move-Item -LiteralPath $deployTarget -Destination $failedDirectory }
    if ($movedPrevious -and -not (Test-Path -LiteralPath $deployTarget)) { Move-Item -LiteralPath $priorDirectory -Destination $deployTarget }
    if ($movedLegacy -and -not (Test-Path -LiteralPath $legacyTarget)) { Move-Item -LiteralPath $legacyDirectory -Destination $legacyTarget }
    throw $installFailure
}
$receipt = [ordered]@{
    version=$releaseVersion;created=(Get-Date).ToString('o');source=$sourceRoot;installed=$deployTarget
    releaseArchive=$releaseArchive;previousArchive=$priorArchive;legacyArchive=$legacyArchive
    previousDirectory=$(if($movedPrevious){$priorDirectory}else{$null})
    legacyDirectory=$(if($movedLegacy){$legacyDirectory}else{$null})
    configBackup=$configBackup;files=$verifiedFiles
}
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8
Write-Output "Installed: $deployTarget"
Write-Output "Verified files: $($verifiedFiles.Count)"
Write-Output "Release archive: $releaseArchive"
Write-Output "Previous archive: $priorArchive"
Write-Output "Legacy archive: $legacyArchive"
Write-Output "Config backup: $configBackup"
Write-Output "Receipt: $receiptPath"
Write-Output 'Server process was not restarted. The resource will start from server.cfg on the next server start.'
