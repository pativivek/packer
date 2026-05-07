###############################################################################
#  cleanup-sysprep.ps1  (AWS-specific)
#  Final pass before AMI capture. Clears state and runs EC2Launch sysprep.
#  Must be the LAST provisioner in the AWS Windows build.
###############################################################################

$ErrorActionPreference = "Stop"
function Log($m) { Write-Host "[cleanup] $m" -ForegroundColor Yellow }

Log "Clearing temp directories"
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\Windows\Temp\*
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\Users\Administrator\AppData\Local\Temp\*

Log "Clearing event logs"
wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }

Log "Removing Windows Update download cache"
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\Windows\SoftwareDistribution\Download\*
Start-Service wuauserv -ErrorAction SilentlyContinue

Log "Triggering EC2Launch v2 sysprep (resets Administrator password on next boot)"

# EC2Launch v2 (Windows Server 2022): use the sysprep schedule command
$ec2LaunchV2 = "C:\Program Files\Amazon\EC2Launch\EC2Launch.exe"
$ec2LaunchV1 = "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\InitializeInstance.ps1"

if (Test-Path $ec2LaunchV2) {
    Log "Using EC2Launch v2"
    & $ec2LaunchV2 reset --block
    & $ec2LaunchV2 sysprep --block --shutdown
}
elseif (Test-Path $ec2LaunchV1) {
    Log "Using EC2Launch v1 (fallback)"
    & $ec2LaunchV1 -Schedule
    & "C:\ProgramData\Amazon\EC2-Windows\Launch\Scripts\SysprepInstance.ps1" -NoShutdown
    Stop-Computer -Force
}
else {
    Log "EC2Launch not found — running plain sysprep"
    & "$env:WINDIR\System32\Sysprep\sysprep.exe" /generalize /oobe /shutdown /quiet
}
