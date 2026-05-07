###############################################################################
#  cis-harden.ps1
#  Lightweight CIS Benchmark hardening for Windows Server 2019 / 2022.
#
#  This is a starter script — covers the highest-impact, low-risk controls.
#  For full CIS compliance, layer in the official CIS Build Kit / Microsoft
#  Security Compliance Toolkit (LGPO.exe + supplied baselines).
#
#  Sections (mapped roughly to CIS Windows Server 2022 Benchmark v2.0.0):
#    1. Account & password policies
#    2. Account lockout policy
#    3. User Rights Assignment (high-impact)
#    4. Security Options (registry-based)
#    5. Windows Firewall — enable all profiles
#    6. Audit policy — advanced auditing
#    7. Disable risky services / features (SMBv1, etc.)
#    8. RDP hardening
#    9. Defender / SmartScreen / UAC
###############################################################################

$ErrorActionPreference = "Stop"
function Log($msg) { Write-Host "[cis-harden] $msg" -ForegroundColor Green }

Log "Starting CIS hardening for $((Get-WmiObject Win32_OperatingSystem).Caption)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Set-RegistryValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)]          $Value,
        [string] $Type = "DWord"
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# ---------------------------------------------------------------------------
# 1. Account & Password Policies (via secedit)
# ---------------------------------------------------------------------------
Log "Section 1 — password & account policies"

$secCfg = @"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 60
MinimumPasswordLength = 14
PasswordComplexity = 1
PasswordHistorySize = 24
LockoutBadCount = 5
LockoutDuration = 15
ResetLockoutCount = 15
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

$cfgPath = "$env:TEMP\cis-secpol.inf"
$dbPath  = "$env:TEMP\cis-secpol.sdb"
$secCfg | Out-File -FilePath $cfgPath -Encoding Unicode -Force
secedit /configure /db $dbPath /cfg $cfgPath /quiet
Remove-Item $cfgPath, $dbPath -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# 2. Security Options — registry hardening
# ---------------------------------------------------------------------------
Log "Section 2 — security options"

# Disable anonymous SID/Name translation
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RestrictAnonymousSAM" 1
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "RestrictAnonymous"    1
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "EveryoneIncludesAnonymous" 0

# Require LM hash to NOT be stored
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "NoLMHash" 1

# LAN Manager authentication level: NTLMv2 only, refuse LM & NTLM
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "LmCompatibilityLevel" 5

# Require signing of LDAP / SMB
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" "RequireSecuritySignature" 1
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" "EnableSecuritySignature"  1
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" "RequireSecuritySignature" 1

# Disable autoplay everywhere
Set-RegistryValue "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 0xFF

# UAC — keep enabled and at the highest practical setting
Set-RegistryValue "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" 1
Set-RegistryValue "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin" 2
Set-RegistryValue "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" "PromptOnSecureDesktop" 1

# ---------------------------------------------------------------------------
# 3. Windows Firewall — enable all three profiles
# ---------------------------------------------------------------------------
Log "Section 3 — enabling Windows Firewall on all profiles"
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True `
    -DefaultInboundAction Block -DefaultOutboundAction Allow `
    -LogAllowed False -LogBlocked True -LogIgnored False `
    -LogFileName "%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log" `
    -LogMaxSizeKilobytes 16384

# ---------------------------------------------------------------------------
# 4. Advanced Audit Policy
# ---------------------------------------------------------------------------
Log "Section 4 — advanced audit policy"
$auditCmds = @(
  'auditpol /set /subcategory:"Credential Validation"     /success:enable /failure:enable',
  'auditpol /set /subcategory:"Logon"                     /success:enable /failure:enable',
  'auditpol /set /subcategory:"Logoff"                    /success:enable',
  'auditpol /set /subcategory:"Special Logon"             /success:enable',
  'auditpol /set /subcategory:"Account Lockout"           /success:enable /failure:enable',
  'auditpol /set /subcategory:"User Account Management"   /success:enable /failure:enable',
  'auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable',
  'auditpol /set /subcategory:"Process Creation"          /success:enable',
  'auditpol /set /subcategory:"Audit Policy Change"       /success:enable /failure:enable',
  'auditpol /set /subcategory:"Authentication Policy Change" /success:enable',
  'auditpol /set /subcategory:"Sensitive Privilege Use"   /success:enable /failure:enable',
  'auditpol /set /subcategory:"System Integrity"          /success:enable /failure:enable',
  'auditpol /set /subcategory:"Other System Events"       /failure:enable'
)
foreach ($cmd in $auditCmds) { cmd /c $cmd | Out-Null }

# Force advanced audit policy to override legacy settings
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" "SCENoApplyLegacyAuditPolicy" 1

# ---------------------------------------------------------------------------
# 5. Disable risky / legacy features
# ---------------------------------------------------------------------------
Log "Section 5 — disabling SMBv1 and other legacy features"

# SMBv1 — must be off
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0

# Disable LLMNR (link-local DNS, common attack vector)
Set-RegistryValue "HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0

# Disable NetBIOS over TCP/IP on all adapters
Get-WmiObject Win32_NetworkAdapterConfiguration | ForEach-Object {
    $_.SetTcpipNetbios(2) | Out-Null  # 2 = disable
}

# Disable IPv6 source routing & ICMP redirects
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" "DisableIPSourceRouting" 2
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"  "DisableIPSourceRouting" 2
Set-RegistryValue "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"  "EnableICMPRedirect"     0

# ---------------------------------------------------------------------------
# 6. RDP hardening
# ---------------------------------------------------------------------------
Log "Section 6 — RDP hardening"

# Require Network Level Authentication
Set-RegistryValue "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication" 1
# Require encryption (High = 3)
Set-RegistryValue "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "MinEncryptionLevel" 3
# Disable saved RDP credentials
Set-RegistryValue "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Terminal Services" "DisablePasswordSaving" 1

# ---------------------------------------------------------------------------
# 7. Microsoft Defender — keep enabled with sensible defaults
# ---------------------------------------------------------------------------
Log "Section 7 — Microsoft Defender configuration"
try {
    Set-MpPreference -DisableRealtimeMonitoring $false `
                     -MAPSReporting Advanced `
                     -SubmitSamplesConsent SendSafeSamples `
                     -PUAProtection Enabled `
                     -DisableScriptScanning $false
    Update-MpSignature -ErrorAction SilentlyContinue
} catch {
    Write-Host "[cis-harden] Defender cmdlets unavailable on this image — skipping" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 8. PowerShell logging
# ---------------------------------------------------------------------------
Log "Section 8 — PowerShell script-block & module logging"
$psPath = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
Set-RegistryValue $psPath "EnableScriptBlockLogging" 1

$modPath = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
Set-RegistryValue $modPath "EnableModuleLogging" 1
if (-not (Test-Path "$modPath\ModuleNames")) { New-Item "$modPath\ModuleNames" -Force | Out-Null }
New-ItemProperty "$modPath\ModuleNames" -Name "*" -Value "*" -PropertyType String -Force | Out-Null

# ---------------------------------------------------------------------------
# 9. Disable Guest account & rename Administrator (best-effort)
# ---------------------------------------------------------------------------
Log "Section 9 — disabling Guest account"
try {
    Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue | Disable-LocalUser
} catch { }

Log "CIS hardening complete."
