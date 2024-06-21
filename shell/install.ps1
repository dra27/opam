<#
  .SYNOPSIS
  Downloads and installs opam from binaries distributed on GitHub.

  .DESCRIPTION
  Script is able to perform either a per-machine or per-user installation of
  opam for any version of opam after 2.2.0~beta2. By default it will install the
  latest released version.

  .LINK
  See https://opam.ocaml.org/doc/Install.html for further information.
#>

param (
  # Install the latest alpha, beta or rc
  [switch]$Dev,
  # Install this specific version of opam instead of the latest
  [string]$Version = "2.2.0~rc1",
  # Specify the installation directory for the opam binary
  [string]$OpamBinDir = $null
)

$DevVersion = "2.2.0~rc1"
$IsAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$DefaultBinDir = If ($IsAdmin) {"$Env:ProgramFiles\opam\bin"} Else {"$Env:LOCALAPPDATA\Programs\opam\bin"}

$SHA512s = @{
  "opam-2.2.0-beta2-x86_64-windows.exe" = "74f034ccc30ef0b2041283ff125be2eab565d4019e79f946b515046c4c290a698266003445f38b91321a9ef931093651f861360906ff06c076c24d18657e2aaf";
  "opam-2.2.0-beta3-x86_64-windows.exe" = "f09337d94e06cedb379c5bf45a50a79cf2b2e529d7c2bb9b35c8a56d40902ff8c7e3f4de9c75fb5c8dd8272b87b2a2645b14e40ef965376ef0d19afd923acf3b";
  "opam-2.2.0-rc1-x86_64-windows.exe" = "f2ec830a5706c45cb56a96713e296ef756c3f2904ca15f7c2ad0442916a9585fa1de8070208f2a6bb3a84dc74b677f946f5bc386c8ed1489da802b1d66a5e094";
}

Function DownloadAndCheck {
  param (
    [string]$OpamBinUrl,
    [string]$OpamBinTmpLoc,
    [string]$OpamBinName
  )

  if (-not $SHA512s.ContainsKey($OpamBinName)) {
    throw "no sha"
  }

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  (New-Object System.Net.WebClient).DownloadFile($OpamBinUrl, $OpamBinTmpLoc)
  $Hash = (Get-FileHash -Path $OpamBinTmpLoc -Algorithm SHA512).Hash

  if ($Hash -ne "$($SHA512s[$OpamBinName])") {
    throw "Checksum mismatch, a problem occurred during download."
  }
}

if (-not [System.Environment]::Is64BitOperatingSystem) {
  throw "opam requires a 64-bit version of Windows"
}

if ($Dev.IsPresent) {
  $Version = $DevVersion
}

$Tag = $Version.Replace("~", "-")
$Arch = "x86_64"
$OS = "windows"
$OpamBinUrlBase = "https://github.com/ocaml/opam/releases/download/"
$OpamBinName = "opam-$Tag-$Arch-$OS.exe"
$OpamBinUrl = "$OpamBinUrlBase$Tag/$OpamBinName"

$OpamBinTmpLoc = "$Env:TEMP\$OpamBinName"

if (-not (Test-Path -Path $OpamBinTmpLoc -IsValid)) {
  throw "Failed to determine a temporary path for downloading opam"
}

Write-Host "## Downloading opam $Version for Windows on x86_64"
$esc = [char]27

if ([string]::IsNullOrEmpty($OpamBinDir)) {
  $OpamBinDir = Read-Host "## Where should it be installed? [$esc[1m$DefaultBinDir$esc[0m]"
  if ([string]::IsNullOrEmpty($OpamBinDir)) {
    $OpamBinDir = $DefaultBinDir
  }
}

if (-not (Test-Path -Path $OpamBinDir -IsValid) -or $OpamBinDir -contains ';') {
  throw "Destination given for installation is not a valid path"
}

# Check existing opam binaries
$AllOpam = Get-Command -All -Name opam -CommandType Application -ErrorAction Ignore | ForEach-Object -MemberName Source
foreach($OneOpam in $AllOpam) {
  if ($OneOpam -ne "$OpamBinDir\opam.exe") {
    throw "We detected another opam binary installed at '$OneOpam'. To ensure problems won't occur later, please uninstall it or remove it from the PATH"
  }
}

DownloadAndCheck -OpamBinUrl $OpamBinUrl -OpamBinTmpLoc $OpamBinTmpLoc -OpamBinName $OpamBinName

# Install the binary
if (-not (Test-Path -Path $OpamBinDir -PathType Container)) {
  [void](New-Item -Force -Path $OpamBinDir -Type Directory)
}
[void](Move-Item -Force -Path $OpamBinTmpLoc -Destination "$OpamBinDir\opam.exe")

# Add the newly installed binary to PATH for this and future sessions
$EnvTarget = If ($IsAdmin) {'MACHINE'} Else {'USER'}
foreach ($loc in $EnvTarget, 'PROCESS') {
  $PATH = [Environment]::GetEnvironmentVariable('PATH', $loc)
  if (-not ($PATH -split ';' -contains $OpamBinDir)) {
    [Environment]::SetEnvironmentVariable('PATH', "$OpamBinDir;$PATH", $loc)
  }
}

Write-Host "## opam $Version installed to $OpamBinDir"
