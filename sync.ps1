param(
  [switch]$Connect,
  [switch]$EnableAuto,
  [switch]$DisableAuto,
  [switch]$Loop
)
# git writes normal progress to stderr and returns non-zero for harmless cases
# (nothing to commit, unset config) — don't let any of that abort the script
$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false
$root = $PSScriptRoot
Set-Location $root

# --- locate git (PATH, or bundled with GitHub Desktop) ---
function Resolve-Git {
  $c = Get-Command git -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $paths = @(
    "$env:LOCALAPPDATA\GitHubDesktop\app-*\resources\app\git\cmd\git.exe",
    "$env:ProgramFiles\Git\cmd\git.exe",
    "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
  )
  foreach ($p in $paths) {
    $hit = Get-ChildItem $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  throw "Git not found. Install Git or GitHub Desktop, then try again."
}
$git = Resolve-Git

# ================= DISABLE AUTO =================
if ($DisableAuto) {
  $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'JointSpaceSync.lnk'
  if (Test-Path $lnk) { Remove-Item $lnk -Force }
  Write-Host "Auto-sync disabled. (A loop already running will stop at your next login.)" -ForegroundColor Yellow
  return
}

# ================= CONNECT =================
if ($Connect) {
  if (-not (Test-Path (Join-Path $root '.git'))) {
    & $git init | Out-Null
    & $git branch -M main
  }
  if (-not (& $git config user.name))  { & $git config user.name  "Kaijuchu" }
  if (-not (& $git config user.email)) { & $git config user.email "taifalsabti@gmail.com" }
  $url = Read-Host "Paste your GitHub repo URL (e.g. https://github.com/Kaijuchu/joint-space.git)"
  if ([string]::IsNullOrWhiteSpace($url)) { Write-Host "No URL entered - cancelled."; return }
  if ((& $git remote) -contains 'origin') { & $git remote set-url origin $url } else { & $git remote add origin $url }
  # if the repo already has commits (e.g. you uploaded index.html via the web), adopt that history
  & $git fetch origin 2>$null | Out-Null
  & $git rev-parse --verify --quiet origin/main | Out-Null
  if ($LASTEXITCODE -eq 0) { & $git reset --soft origin/main }
  & $git add -A
  & $git commit -m "Initial commit: Joint Space" 2>$null | Out-Null
  & $git push -u origin main
  Write-Host "Connected and pushed to $url" -ForegroundColor Green
  return
}

# ================= ENABLE AUTO =================
if ($EnableAuto) {
  $startup = [Environment]::GetFolderPath('Startup')
  $lnk = Join-Path $startup 'JointSpaceSync.lnk'
  $vbs = Join-Path $root 'start-sync-hidden.vbs'
  $ws  = New-Object -ComObject WScript.Shell
  $sc  = $ws.CreateShortcut($lnk)
  $sc.TargetPath       = "wscript.exe"
  $sc.Arguments        = '"' + $vbs + '"'
  $sc.WorkingDirectory = $root
  $sc.Save()
  Start-Process wscript.exe -ArgumentList ('"' + $vbs + '"')
  Write-Host "Auto-sync enabled: runs now, at every login, and every 15 minutes." -ForegroundColor Green
  return
}

# ================= SYNC LOGIC =================
function Build-Message {
  $num = & $git diff --cached --numstat
  $add = 0; $del = 0; $files = @()
  foreach ($l in $num) {
    if ($l -match '^\s*(\d+|-)\s+(\d+|-)\s+(.+)$') {
      if ($matches[1] -ne '-') { $add += [int]$matches[1] }
      if ($matches[2] -ne '-') { $del += [int]$matches[2] }
      $files += $matches[3]
    }
  }
  $diff = (& $git diff --cached) -join "`n"
  $areas = @()
  if ($diff -match 'jointAuth|signInWith|supabase|authenticate|signOut') { $areas += 'auth' }
  if ($diff -match 'JOINT_GEM_KEY|gemini|generativelanguage|Spacey|claude\.complete|gemKey') { $areas += 'Spacey/AI' }
  if ($diff -match '@keyframes|border-radius|linear-gradient|font:\s|color:\s|background:') { $areas += 'styling' }
  if ($diff -match 'setState|componentDidMount|enterSpace|view:|space:|toggle') { $areas += 'logic' }
  $areas = $areas | Select-Object -Unique
  $head = "Update Joint Space"
  if ($areas.Count) { $head += ": " + ($areas -join ", ") }
  $head += " (+$add/-$del)"
  return $head
}

function Sync-Once {
  & $git add -A
  $status = & $git status --porcelain
  if ([string]::IsNullOrWhiteSpace(($status -join ''))) { return $false }
  $msg = Build-Message
  & $git commit -m $msg | Out-Null
  & $git push origin main 2>$null
  Write-Host ((Get-Date -Format 'HH:mm') + '  ' + $msg)
  return $true
}

# ================= LOOP or ONE-SHOT =================
if ($Loop) {
  # only one loop at a time
  $mtx = New-Object System.Threading.Mutex($false, 'Global\JointSpaceSyncLoop')
  if (-not $mtx.WaitOne(0)) { return }
  while ($true) {
    try { Sync-Once | Out-Null } catch { }
    Start-Sleep -Seconds 900
  }
} else {
  if (-not (Sync-Once)) { Write-Host "Nothing to sync - working tree is clean." -ForegroundColor DarkGray }
}
