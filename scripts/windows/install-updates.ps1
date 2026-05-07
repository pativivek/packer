###############################################################################
#  install-updates.ps1
#  Installs all available Windows security updates via the PSWindowsUpdate
#  module. This is typically the longest step of the build (10-30 minutes).
###############################################################################

$ErrorActionPreference = "Stop"
function Log($m) { Write-Host "[updates] $m" -ForegroundColor Cyan }

Log "Installing NuGet provider"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null

Log "Trusting PSGallery so we can install PSWindowsUpdate non-interactively"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Log "Installing PSWindowsUpdate module"
Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -Scope AllUsers
Import-Module PSWindowsUpdate

Log "Searching for and installing Critical + Security updates (no reboot here)"
Get-WindowsUpdate -MicrosoftUpdate `
                  -Category 'Critical Updates','Security Updates' `
                  -AcceptAll -Install -IgnoreReboot -Verbose

Log "Updates step complete. A reboot may be required and will happen between provisioners."
