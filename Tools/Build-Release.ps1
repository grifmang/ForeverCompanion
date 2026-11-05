[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [ValidateRange(1,9999999)][int]$BuildNumber
)
$ErrorActionPreference = 'Stop'
$taskSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $taskSource 'dist' }
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
$taskLua = @(
    'Core.lua','API.lua','Store.lua','UI/Widgets.lua','UI/Shell.lua',
    'Modules/PriceAPI.lua','Modules/Wallet.lua','Modules/RecipeAPI.lua',
    'Modules/Crafting.lua','Modules/Items.lua','Modules/LegacyAPI.lua',
    'Modules/Legacy.lua','Modules/QuestTracker.lua','Modules/QuestData.lua','Modules/QuestRoute.lua',
    'Modules/QuestGuide.lua','Modules/QuestHUD.lua','Modules/QuestSync.lua',
    'Modules/QuestLogUI.lua','Modules/ObjectiveTrackerUI.lua','Modules/Adventure.lua',
    'Modules/Updates.lua','Modules/PartyProtocol.lua','Startup.lua'
)
$taskDocs = @('ForeverCompanion.toc','ForeverCompanion_Camelot.toc','README.md','CHANGELOG.md','LICENSE','ACCEPTANCE.md','VERIFICATION.md')
$taskAllowlist = [string[]]($taskLua + $taskDocs)
[Array]::Sort($taskAllowlist,[StringComparer]::Ordinal)

function Assert-RegularInput([string]$RelativePath) {
    if ($RelativePath -notin $taskAllowlist -or $RelativePath -match '(^|/)\.\.?(/|$)|\\|:' -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Disallowed input path: $RelativePath"
    }
    $taskPath = [IO.Path]::GetFullPath((Join-Path $taskSource $RelativePath))
    if (-not $taskPath.StartsWith($taskSource + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Input escapes source.' }
    $taskCheck = $taskPath
    while ($true) {
        $taskItem = Get-Item -LiteralPath $taskCheck -Force
        if (($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked input is forbidden: $RelativePath" }
        if ($taskCheck -eq $taskSource) { break }
        $taskCheck = [IO.Path]::GetDirectoryName($taskCheck)
    }
    if (-not (Test-Path -LiteralPath $taskPath -PathType Leaf)) { throw "Missing input: $RelativePath" }
    return $taskPath
}

foreach ($taskRelative in $taskAllowlist) { $null = Assert-RegularInput $taskRelative }
$taskToc = Get-Content -LiteralPath (Join-Path $taskSource 'ForeverCompanion.toc') -Raw
$taskFlavorToc = Get-Content -LiteralPath (Join-Path $taskSource 'ForeverCompanion_Camelot.toc') -Raw
if ($taskToc -cne $taskFlavorToc) { throw 'Flavor TOCs differ.' }
$taskEntries = @(($taskToc -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($taskEntries.Count -ne $taskLua.Count) { throw 'Expected exactly 20 runtime Lua paths.' }
for ($taskIndex=0; $taskIndex -lt $taskLua.Count; $taskIndex++) {
    if ($taskEntries[$taskIndex] -cne $taskLua[$taskIndex]) { throw "Unexpected runtime order/path at index ${taskIndex}: $($taskEntries[$taskIndex])" }
}
if (-not ($taskToc -match '(?m)^## SavedVariables: ForeverCompanionDB\r?$')) { throw 'SavedVariables declaration differs.' }
$taskVersions = [regex]::Matches($taskToc,'(?m)^## Version: ([^\r\n]+)\r?$')
if ($taskVersions.Count -ne 1) { throw 'Expected one TOC version.' }
$taskBaseVersion = $taskVersions[0].Groups[1].Value
if ($taskBaseVersion -notmatch '^\d+\.\d+\.\d+-prototype$') { throw 'Source must use a canonical base prototype version without a build suffix.' }
$taskCore = Get-Content -LiteralPath (Join-Path $taskSource 'Core.lua') -Raw
$taskCoreVersions = [regex]::Matches($taskCore,'FC\.name,\s*FC\.version\s*=\s*addonName,\s*"([^"]+)"')
if ($taskCoreVersions.Count -ne 1 -or $taskCoreVersions[0].Groups[1].Value -cne $taskBaseVersion) { throw 'Core and TOC base versions differ.' }
$taskVersion = if ($PSBoundParameters.ContainsKey('BuildNumber')) { "$taskBaseVersion.$BuildNumber" } else { $taskBaseVersion }

if (-not (Test-Path -LiteralPath $taskOutput)) { $null = New-Item -ItemType Directory -Path $taskOutput }
if (-not (Test-Path -LiteralPath $taskOutput -PathType Container)) { throw 'Output path must be a directory.' }
if (((Get-Item -LiteralPath $taskOutput -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Output directory must not be linked.' }
$taskStageParent = [IO.Path]::GetFullPath((Join-Path $taskOutput ('stage-' + $taskVersion + '-' + [guid]::NewGuid().ToString('N'))))
if (-not $taskStageParent.StartsWith($taskOutput.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Stage escapes output directory.' }
$taskStage = Join-Path $taskStageParent 'ForeverCompanion'
$taskArchive = Join-Path $taskOutput ('ForeverCompanion-' + $taskVersion + '-forever.zip')
$taskSidecar = $taskArchive + '.sha256'
$taskMetadata = Join-Path $taskOutput ('ForeverCompanion-' + $taskVersion + '.json')
foreach ($taskDestination in @($taskStageParent,$taskArchive,$taskSidecar,$taskMetadata)) {
    if (Test-Path -LiteralPath $taskDestination) { throw "Refusing to overwrite release output: $taskDestination" }
}
$null = New-Item -ItemType Directory -Path $taskStage
foreach ($taskRelative in $taskAllowlist) {
    $taskDestination = Join-Path $taskStage $taskRelative
    $taskParent = [IO.Path]::GetDirectoryName($taskDestination)
    if (-not (Test-Path -LiteralPath $taskParent)) { $null = New-Item -ItemType Directory -Path $taskParent }
    Copy-Item -LiteralPath (Assert-RegularInput $taskRelative) -Destination $taskDestination
}
foreach ($taskName in @('ForeverCompanion.toc','ForeverCompanion_Camelot.toc')) {
    $taskStamped = $taskToc.Replace('## Version: ' + $taskBaseVersion,'## Version: ' + $taskVersion)
    [IO.File]::WriteAllText((Join-Path $taskStage $taskName),$taskStamped,[Text.UTF8Encoding]::new($false))
}
$taskStampedCore = $taskCore.Replace($taskCoreVersions[0].Value,'FC.name, FC.version = addonName, "' + $taskVersion + '"')
[IO.File]::WriteAllText((Join-Path $taskStage 'Core.lua'),$taskStampedCore,[Text.UTF8Encoding]::new($false))
$taskManifest = foreach ($taskRelative in $taskAllowlist) {
    [pscustomobject]@{Path=$taskRelative;SHA256=(Get-FileHash -LiteralPath (Join-Path $taskStage $taskRelative) -Algorithm SHA256).Hash.ToLowerInvariant()}
}

# Fixed entry order, timestamps and a single explicit root. Never zip the checkout.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskZip = [IO.Compression.ZipFile]::Open($taskArchive,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($taskRelative in $taskAllowlist) {
        $taskEntry = $taskZip.CreateEntry('ForeverCompanion/' + $taskRelative,[IO.Compression.CompressionLevel]::Optimal)
        $taskEntry.LastWriteTime = [DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
        $taskInput = [IO.File]::OpenRead((Join-Path $taskStage $taskRelative))
        $taskEntryStream = $taskEntry.Open()
        try { $taskInput.CopyTo($taskEntryStream) } finally { $taskEntryStream.Dispose(); $taskInput.Dispose() }
    }
} finally { $taskZip.Dispose() }

$taskZip = [IO.Compression.ZipFile]::OpenRead($taskArchive)
try {
    if ($taskZip.Entries.Count -ne $taskAllowlist.Count) { throw 'Archive entry count differs from allowlist.' }
    foreach ($taskFile in $taskManifest) {
        $taskEntry = $taskZip.GetEntry('ForeverCompanion/' + $taskFile.Path)
        if (-not $taskEntry) { throw "Missing archive entry: $($taskFile.Path)" }
        $taskStream = $taskEntry.Open()
        $taskHasher = [Security.Cryptography.SHA256]::Create()
        try { $taskHash = [BitConverter]::ToString($taskHasher.ComputeHash($taskStream)).Replace('-','').ToLowerInvariant() }
        finally { $taskStream.Dispose(); $taskHasher.Dispose() }
        if ($taskHash -cne $taskFile.SHA256) { throw "Archive content mismatch: $($taskFile.Path)" }
    }
} finally { $taskZip.Dispose() }
$taskArchiveHash = (Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($taskSidecar,$taskArchiveHash + '  ' + [IO.Path]::GetFileName($taskArchive) + "`n",[Text.UTF8Encoding]::new($false))
$taskResult = [pscustomobject]@{
    BaseVersion=$taskBaseVersion;Version=$taskVersion;BuildNumber=if ($PSBoundParameters.ContainsKey('BuildNumber')) {$BuildNumber} else {$null}
    Tag='v' + $taskVersion;Archive=$taskArchive;SHA256File=$taskSidecar;Metadata=$taskMetadata;Stage=$taskStage
    ArchiveSHA256=$taskArchiveHash;Files=@($taskManifest)
}
$taskResult | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskMetadata -Encoding utf8NoBOM
Write-Host "Packaged $($taskAllowlist.Count) allowlisted files: $taskArchive"
return $taskResult
