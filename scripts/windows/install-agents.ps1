###############################################################################
#  install-agents.ps1
#  Installs cloud-specific agents on Windows. Set $env:CLOUD before running.
###############################################################################

$ErrorActionPreference = "Stop"
function Log($m) { Write-Host "[agents] $m" -ForegroundColor Blue }

$cloud = if ($env:CLOUD) { $env:CLOUD } else { "aws" }
Log "Installing agents for cloud=$cloud"

# --- Common: ensure NTP / time sync is healthy ---
Log "Configuring Windows Time"
w32tm /config /manualpeerlist:"time.windows.com,0x9" /syncfromflags:manual /reliable:yes /update | Out-Null
Restart-Service w32time -ErrorAction SilentlyContinue

switch ($cloud) {
    "aws" {
        Log "AWS — installing SSM Agent and CloudWatch Agent"

        $ssmInstaller = "$env:TEMP\AmazonSSMAgentSetup.exe"
        Invoke-WebRequest -Uri "https://amazon-ssm-region.s3.amazonaws.com/latest/windows_amd64/AmazonSSMAgentSetup.exe" `
                          -OutFile $ssmInstaller -UseBasicParsing
        Start-Process -FilePath $ssmInstaller -ArgumentList "/S" -Wait
        Set-Service AmazonSSMAgent -StartupType Automatic

        $cwInstaller = "$env:TEMP\amazon-cloudwatch-agent.msi"
        Invoke-WebRequest -Uri "https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi" `
                          -OutFile $cwInstaller -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i $cwInstaller /quiet" -Wait
    }

    "azure" {
        Log "Azure — VM Agent is preinstalled on marketplace images. Verifying..."
        Get-Service WindowsAzureGuestAgent -ErrorAction SilentlyContinue |
            Set-Service -StartupType Automatic
    }

    "gcp" {
        Log "GCP — guest tools are preinstalled. Verifying GCEAgent."
        Get-Service GCEAgent -ErrorAction SilentlyContinue |
            Set-Service -StartupType Automatic
    }

    default {
        Log "Unknown cloud=$cloud — skipping cloud-specific agents."
    }
}

Log "Agent installation complete."
