$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Refresh-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

function Resolve-Dependency([string]$Command, [string[]]$Candidates) {
  $resolved = Get-Command $Command -ErrorAction SilentlyContinue
  if ($resolved) { return $resolved.Source }
  foreach ($candidate in $Candidates) {
    if (Test-Path -LiteralPath $candidate) {
      $directory = Split-Path -Parent $candidate
      $env:Path = "$directory;$env:Path"
      if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PATH)) {
        $directory | Out-File -FilePath $env:GITHUB_PATH -Append -Encoding utf8
      }
      return $candidate
    }
  }
  return $null
}

function Ensure-WingetDependency(
  [string]$Command,
  [string]$PackageId,
  [string[]]$Candidates
) {
  $path = Resolve-Dependency -Command $Command -Candidates $Candidates
  if ($path) { return $path }
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) { throw "dependency bootstrap cannot install $Command because winget is unavailable" }
  & $winget.Source install --id $PackageId --exact --silent --scope user `
    --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "dependency bootstrap failed for $Command" }
  Refresh-ProcessPath
  $path = Resolve-Dependency -Command $Command -Candidates $Candidates
  if (-not $path) { throw "dependency bootstrap did not install $Command" }
  return $path
}

$localPrograms = Join-Path $env:LOCALAPPDATA 'Programs'
$git = Ensure-WingetDependency git.exe Git.Git @(
  (Join-Path $localPrograms 'Git\cmd\git.exe'),
  (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
)
$gh = Ensure-WingetDependency gh.exe GitHub.cli @(
  (Join-Path $localPrograms 'GitHub CLI\gh.exe'),
  (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe')
)
$pwsh = Ensure-WingetDependency pwsh.exe Microsoft.PowerShell @(
  (Join-Path $localPrograms 'PowerShell\7\pwsh.exe'),
  (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
)

& $git --version | Out-Null
& $gh --version | Out-Null
& $pwsh --version | Out-Null
