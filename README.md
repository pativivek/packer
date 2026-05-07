# Packer Golden Image — AWS, Azure & GCP (Linux + Windows)

Build CIS-hardened **RHEL 9** and **Windows Server 2022** golden images for
AWS, Azure, and GCP from a single repository, locally or via GitHub Actions.

```
packer-golden-image/
├── packer/                              # HCL templates
│   ├── aws.pkr.hcl                      # Linux (RHEL 9)
│   ├── azure.pkr.hcl
│   ├── gcp.pkr.hcl
│   ├── aws-windows.pkr.hcl              # Windows (Server 2022)
│   ├── azure-windows.pkr.hcl
│   ├── gcp-windows.pkr.hcl
│   └── variables.pkrvars.hcl.example
├── scripts/
│   ├── cis-harden.sh                    # Linux CIS hardening
│   ├── install-agents.sh
│   ├── cleanup.sh
│   └── windows/                         # Windows provisioners
│       ├── bootstrap-winrm.ps1          #   AWS user-data: enables WinRM
│       ├── install-updates.ps1          #   Windows security updates
│       ├── cis-harden.ps1               #   CIS hardening
│       ├── install-agents.ps1           #   Cloud agents (SSM, CW, etc.)
│       └── cleanup-sysprep.ps1          #   AWS-specific sysprep + cleanup
├── .github/workflows/                   # CI/CD — one workflow per OS+cloud
│   ├── build-aws.yml
│   ├── build-azure.yml
│   ├── build-gcp.yml
│   ├── build-aws-windows.yml
│   ├── build-azure-windows.yml
│   └── build-gcp-windows.yml
├── .gitignore
└── README.md
```

---

## Table of Contents

- [Packer Golden Image — AWS, Azure \& GCP (Linux + Windows)](#packer-golden-image--aws-azure--gcp-linux--windows)
  - [Table of Contents](#table-of-contents)
  - [Quick start](#quick-start)
  - [Prerequisites](#prerequisites)
  - [Local builds — Linux](#local-builds--linux)
    - [AWS](#aws)
    - [Azure](#azure)
    - [GCP](#gcp)
  - [Local builds — Windows](#local-builds--windows)
    - [AWS Windows](#aws-windows)
    - [Azure Windows](#azure-windows)
    - [GCP Windows](#gcp-windows)
  - [GitHub Actions](#github-actions)
    - [AWS via OIDC](#aws-via-oidc)
    - [Azure via Service Principal](#azure-via-service-principal)
    - [GCP via Workload Identity Federation](#gcp-via-workload-identity-federation)
  - [What gets hardened](#what-gets-hardened)
    - [Linux (RHEL/OEL)](#linux-rheloel)
    - [Windows](#windows)
  - [How to extend](#how-to-extend)
  - [License](#license)

---

## Quick start

```bash
git clone https://github.com/<your-org>/packer-golden-image.git
cd packer-golden-image

# Install Packer 1.10+ first (https://developer.hashicorp.com/packer/downloads)
packer version

# Build for AWS (assumes aws cli is configured)
cd packer
packer init  aws.pkr.hcl
packer build aws.pkr.hcl
```

That's it. The first run takes 5–10 minutes; output is a tagged AMI named
`golden-rhel9-<timestamp>`.

---

## Prerequisites

| Tool        | Version | Purpose                          |
|-------------|---------|----------------------------------|
| Packer      | 1.10+   | The image builder itself         |
| Git         | any     | Clone & version templates        |
| AWS CLI     | 2.x     | Local AWS auth (optional)        |
| Azure CLI   | 2.x     | Local Azure auth (optional)      |
| gcloud SDK  | latest  | Local GCP auth (optional)        |

Plus a cloud account with permission to:

- **AWS** — create EC2 instances, AMIs, key pairs, and tag resources
- **Azure** — create VMs and managed images in a resource group
- **GCP** — create Compute Engine instances and custom images

---

## Local builds — Linux

### AWS

```bash
# 1. Configure AWS credentials however you prefer
aws configure              # or: export AWS_PROFILE=...

# 2. Build
cd packer
packer init  aws.pkr.hcl
packer build aws.pkr.hcl
```

Override the region:

```bash
packer build -var aws_region=eu-west-1 aws.pkr.hcl
```

The resulting AMI ID is written to `manifest-aws.json`.

### Azure

```bash
# 1. Create a service principal (one-time)
az login
SUB_ID=$(az account show --query id -o tsv)
az ad sp create-for-rbac \
  --name "packer-builder" \
  --role Contributor \
  --scopes "/subscriptions/$SUB_ID"
# The command prints clientId / password / tenant — save these.

# 2. Create the resource group that will hold images
az group create --name rg-golden-images --location "East US"

# 3. Build
cd packer
export PKR_VAR_client_id="<appId>"
export PKR_VAR_client_secret="<password>"
export PKR_VAR_tenant_id="<tenant>"
export PKR_VAR_subscription_id="$SUB_ID"

packer init  azure.pkr.hcl
packer build azure.pkr.hcl
```

### GCP

```bash
# 1. Authenticate
gcloud auth application-default login
gcloud config set project <your-project-id>

# 2. Enable the Compute Engine API
gcloud services enable compute.googleapis.com

# 3. Build
cd packer
packer init  gcp.pkr.hcl
packer build -var "project_id=$(gcloud config get-value project)" gcp.pkr.hcl
```

If you'd rather use a service-account key file:

```bash
packer build \
  -var "project_id=my-project" \
  -var "credentials_file=./gcp-sa.json" \
  gcp.pkr.hcl
```

---

## Local builds — Windows

Windows builds use **WinRM over HTTPS** instead of SSH. Build times are
significantly longer than Linux (typically 30–60 minutes) because the
`install-updates.ps1` step applies all available Critical / Security
updates from Microsoft Update.

The base image used is **Windows Server 2022 Datacenter** in all three clouds.
To build Server 2019 instead, change `image_sku` (Azure), the AMI filter
(AWS), or `source_image_family` (GCP).

### AWS Windows

```bash
# Authenticate (same as Linux)
aws configure

cd packer
packer init  aws-windows.pkr.hcl
packer build aws-windows.pkr.hcl
```

How it works:

- The `user_data_file` (`scripts/windows/bootstrap-winrm.ps1`) runs at first
  boot and configures a WinRM HTTPS listener with a self-signed cert.
- Packer connects as `Administrator` using the password retrieved via
  `ec2:GetPasswordData` — no key material is stored locally.
- After provisioning, `cleanup-sysprep.ps1` runs **EC2Launch sysprep** so
  every instance launched from the AMI gets a fresh SID and Administrator
  password.

The resulting AMI ID is written to `manifest-aws-windows.json`.

### Azure Windows

```bash
# Same service principal as Linux Azure builds
export PKR_VAR_client_id="<appId>"
export PKR_VAR_client_secret="<password>"
export PKR_VAR_tenant_id="<tenant>"
export PKR_VAR_subscription_id="<subId>"

cd packer
packer init  azure-windows.pkr.hcl
packer build azure-windows.pkr.hcl
```

The `azure-arm` builder handles WinRM setup and runs **`waagent
-deprovision`** + sysprep automatically — there is no manual sysprep step.

### GCP Windows

```bash
gcloud auth application-default login

cd packer
packer init  gcp-windows.pkr.hcl
packer build -var "project_id=$(gcloud config get-value project)" gcp-windows.pkr.hcl
```

The `googlecompute` builder enables WinRM through the `metadata` block (a
`sysprep-specialize-script-cmd`), so no user-data file is needed. The build
finishes by invoking `GCESysprep -NoShutdown` to generalize the image.

---

## GitHub Actions

All workflows support both `workflow_dispatch` (manual) and a `push` to `main`
that touches the relevant template or any provisioner script. There is one
workflow per OS-and-cloud combination — six in total.

```text
.github/workflows/
  build-aws.yml             →  Linux AMI
  build-azure.yml           →  Linux Managed Image
  build-gcp.yml             →  Linux Custom Image
  build-aws-windows.yml     →  Windows AMI
  build-azure-windows.yml   →  Windows Managed Image
  build-gcp-windows.yml     →  Windows Custom Image
```

The Windows workflows use the **same secrets** as their Linux counterparts —
no extra setup is needed beyond what's described below.

### AWS via OIDC

The recommended way — no static keys in GitHub.

1. **Create the GitHub OIDC provider** (one-time per AWS account)

   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create an IAM role** with a trust policy that allows the workflow:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<acct>:oidc-provider/token.actions.githubusercontent.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
         "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:<owner>/<repo>:ref:refs/heads/main" }
       }
     }]
   }
   ```

   Attach a policy granting the EC2 / image permissions Packer needs
   ([reference policy](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#iam-task-or-instance-role)).

3. **Add the secret** in the repo (Settings → Secrets and variables → Actions):

   | Secret          | Value                                   |
   |-----------------|-----------------------------------------|
   | `AWS_ROLE_ARN`  | `arn:aws:iam::<acct>:role/packer-builder` |

4. **Run** — Actions tab → *Build AWS Golden Image* → Run workflow.

### Azure via Service Principal

1. Create the service principal as shown in [Local builds → Azure](#azure).

2. Add four repository secrets:

   | Secret                    | Value                  |
   |---------------------------|------------------------|
   | `AZURE_CLIENT_ID`         | service principal appId |
   | `AZURE_CLIENT_SECRET`     | service principal password |
   | `AZURE_TENANT_ID`         | Azure AD tenant id     |
   | `AZURE_SUBSCRIPTION_ID`   | target subscription id |

3. Make sure the resource group `rg-golden-images` exists (or change it in
   `build-azure.yml`).

4. Run the workflow.

### GCP via Workload Identity Federation

Like AWS OIDC — no service-account JSON keys in the repo.

1. **Set up Workload Identity Federation** (one-time per GCP project), then
   bind a service account that the workflow can impersonate. See
   [google-github-actions/auth setup guide](https://github.com/google-github-actions/auth#setup).

2. Add three repository secrets:

   | Secret                              | Value                                          |
   |-------------------------------------|------------------------------------------------|
   | `GCP_PROJECT_ID`                    | your-project-id                                |
   | `GCP_WORKLOAD_IDENTITY_PROVIDER`    | `projects/<num>/locations/global/workloadIdentityPools/<pool>/providers/<provider>` |
   | `GCP_SERVICE_ACCOUNT`               | `packer-builder@<project>.iam.gserviceaccount.com` |

3. The service account needs roles:
   `roles/compute.instanceAdmin.v1`, `roles/iam.serviceAccountUser`,
   `roles/compute.storageAdmin`.

4. Run the workflow.

---

## What gets hardened

### Linux (RHEL/OEL)

`scripts/cis-harden.sh` is a **starter** CIS Benchmark profile for RHEL 9 /
Oracle Linux 8–9. It covers the high-impact, low-risk controls:

| Section                         | What it does                                               |
|---------------------------------|------------------------------------------------------------|
| 1. Filesystem & kernel modules  | Disables cramfs, hfs, squashfs, USB storage, etc.          |
| 2. Legacy services              | Removes telnet/rsh/ypserv/tftp; disables xinetd & avahi    |
| 3. Network sysctls              | Disables IP forwarding, source routing, ICMP redirects     |
| 4. Logging & auditing           | Enables `auditd` + `rsyslog` with the CIS baseline rules   |
| 5. SSH                          | Disables root login, password auth, sets aggressive timeouts |
| 6. Password policy              | Aging rules, locked system accounts, restricted cron/at   |
| 7. Patching                     | Applies all available security updates                     |

For full CIS compliance, layer in **OpenSCAP** with the
[SCAP Security Guide](https://github.com/ComplianceAsCode/content) (package
`scap-security-guide`). Add a provisioner like:

```hcl
provisioner "shell" {
  inline = [
    "sudo dnf -y install scap-security-guide",
    "sudo oscap xccdf eval --profile cis --remediate /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml || true"
  ]
}
```

### Windows

`scripts/windows/cis-harden.ps1` is a **starter** CIS Benchmark profile for
Windows Server 2019/2022. It covers:

| Section                         | What it does                                               |
|---------------------------------|------------------------------------------------------------|
| 1. Account & password policies  | 14-char min, 60-day max, complexity, 24-history (`secedit`) |
| 2. Security options             | Disables anonymous SAM, NoLMHash, NTLMv2 only, SMB signing |
| 3. Windows Firewall             | Enables all three profiles, default-block inbound          |
| 4. Advanced Audit Policy        | Logon, account mgmt, process creation, policy change, etc. |
| 5. Legacy features              | Disables SMBv1, LLMNR, NetBIOS over TCP/IP, IP source routing |
| 6. RDP hardening                | Forces NLA, high encryption, no saved credentials          |
| 7. Microsoft Defender           | Real-time protection, MAPS, PUA protection on              |
| 8. PowerShell logging           | Script-block + module logging enabled                      |
| 9. Account hygiene              | Disables Guest account                                     |

For full CIS compliance, use the **Microsoft Security Compliance Toolkit**
([download](https://www.microsoft.com/en-us/download/details.aspx?id=55319))
together with `LGPO.exe` to apply the official CIS-aligned baselines:

```powershell
# In a provisioner, after downloading the toolkit + baselines:
& 'C:\baselines\LGPO.exe' /g 'C:\baselines\Windows-Server-2022-Member-Server'
```

---

## How to extend

- **Add an Ansible step** — replace any `provisioner "shell"` with
  `provisioner "ansible" { playbook_file = "..." }`.
- **Add Ubuntu/Debian** — copy `aws.pkr.hcl` to `aws-ubuntu.pkr.hcl`, change
  the `source_ami_filter` and `ssh_username`, and write a parallel hardening
  script.
- **Multi-region AWS** — turn `aws_region` into a list and use a
  `dynamic "source"` block, or add `ami_regions = ["us-east-1", "eu-west-1"]`
  to the source block to copy the AMI after build.
- **Tagging strategy** — extend the `tags` / `azure_tags` / `image_labels`
  blocks with cost-center, owner, and patch-baseline metadata.

---

## License

MIT — use it, fork it, ship it.