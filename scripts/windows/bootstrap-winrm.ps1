<powershell>
###############################################################################
#  bootstrap-winrm.ps1  —  AWS user-data
#  Runs on the very first boot of the temporary Packer instance and configures
#  WinRM so Packer can connect over HTTPS with a self-signed certificate.
#
#  This script is referenced from aws-windows.pkr.hcl via `user_data_file`.
###############################################################################

# Generate a self-signed cert and configure HTTPS WinRM listener
$cert = New-SelfSignedCertificate -DnsName "packer-winrm" `
                                  -CertStoreLocation Cert:\LocalMachine\My
$thumb = $cert.Thumbprint

# Remove any pre-existing HTTPS listener, then create ours
winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>$null
$selector = '@{Hostname="packer-winrm"; CertificateThumbprint="' + $thumb + '"}'
winrm create winrm/config/Listener?Address=*+Transport=HTTPS $selector

# Auth + service settings Packer needs
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service       '@{AllowUnencrypted="true"}'
winrm set winrm/config/client/auth   '@{Basic="true"}'

# Open the firewall
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound `
                    -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue

# Restart the service so settings take effect
Restart-Service WinRM

# Allow the EC2 launch wizard to set the Administrator password
$adminPw = (Get-EC2InstanceMetadata -Category UserData -ErrorAction SilentlyContinue) 2>$null
if (-not $adminPw) {
    # Reset Administrator password to a random one — Packer will retrieve it
    # via ec2:GetPasswordData (handled by the amazon-ebs builder automatically
    # when winrm_password is unset).
    Write-Host "Letting Packer retrieve Administrator password from instance metadata."
}
</powershell>
<persist>true</persist>
