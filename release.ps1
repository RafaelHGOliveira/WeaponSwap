# Releases WeaponSwap: test, bump the .toc, commit, tag, push, zip, upload to CurseForge,
# copy into the game. Usage: pwsh -File release.ps1 1.3.2 path\to\changelog.md
param(
  [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
  [Parameter(Mandatory)][string]$Changelog
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ProjectId = 1809071
$GameVersion = 17053 # WoW Forever 1.60.1 on CurseForge
$TokenFile = "$HOME\.config\curseforge\api-token"
$AddOns = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WeaponSwap'

function Assert-Ok($what) { if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" } }

$notes = Get-Content -Raw $Changelog
if (git status --porcelain) { throw 'working tree is not clean: commit or stash first' }
if ((git branch --show-current) -ne 'main') { throw 'not on main' }
if (git tag --list "v$Version") { throw "tag v$Version already exists" }

uv run -q tests/test_macros.py; Assert-Ok 'tests'

$toc = Get-Content -Raw WeaponSwap.toc
$bumped = $toc -replace '(?m)^## Version: .*$', "## Version: $Version"
if ($bumped -ceq $toc) { throw "WeaponSwap.toc already says $Version" }
Set-Content WeaponSwap.toc $bumped -NoNewline
git commit -q -am "Release $Version"; Assert-Ok 'commit'
git tag "v$Version"; Assert-Ok 'tag'
git push -q origin main --tags; Assert-Ok 'push'

$zip = Join-Path ([IO.Path]::GetTempPath()) "WeaponSwap-$Version.zip"
git archive --format=zip --prefix=WeaponSwap/ -o $zip "v$Version"; Assert-Ok 'archive'

$metadata = @{
  changelog     = $notes
  changelogType = 'markdown'
  displayName   = "WeaponSwap $Version"
  gameVersions  = @($GameVersion)
  releaseType   = 'release'
} | ConvertTo-Json -Compress
$headers = @{ 'X-Api-Token' = (Get-Content -Raw $TokenFile).Trim() }
$upload = Invoke-RestMethod -Method Post -Headers $headers `
  -Uri "https://wow.curseforge.com/api/projects/$ProjectId/upload-file" `
  -Form @{ metadata = $metadata; file = Get-Item $zip }
"CurseForge file $($upload.id)"

Copy-Item WeaponSwap.lua, WeaponSwap.toc $AddOns
"v$Version released and copied to $AddOns"
