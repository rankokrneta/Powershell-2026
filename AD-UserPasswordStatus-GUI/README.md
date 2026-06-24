# AD User Password / Lockout Check

Created by **Ranko Krneta**  
Version: **1.7.1-github-clean**

Project location:

```text
Powershell 2026
└── AD-UserPasswordStatus-GUI
```

A small Windows PowerShell GUI for checking Active Directory user password and lockout status, with an optional unlock action when the operator has permission.

This GitHub-clean version intentionally contains **no hardcoded domain controllers, domains, IP addresses, usernames, or company-specific values**.

## Features

- Check AD user by `samAccountName`, UPN, or email.
- Show password/lockout information:
  - Enabled
  - Locked out
  - Password expired
  - Password last set
  - Password expiry
  - Days until expiry
  - Last bad password attempt
  - Bad password count
  - Account lockout time
- Unlock locked AD accounts if your account has permission.
- Add/remove/persist your own Domain Controllers locally.
- Discover DCs from AD/DNS where possible.
- Test DC connectivity on:
  - TCP 9389 - AD Web Services / AD PowerShell cmdlets
  - TCP 389 - LDAP
  - TCP 88 - Kerberos
- Optional Advanced Credentials dialog.
- Optional DPAPI-protected saved credential for the current Windows user/profile.

## Files

```text
Powershell 2026/
├── README.md
├── .gitignore
└── AD-UserPasswordStatus-GUI/
    ├── AD-UserPasswordStatus-GUI.ps1
    ├── Start-AD-UserPasswordStatus-GUI.bat
    ├── Install-From-GitHub.bat
    ├── README.md
    ├── README_AD_UserPasswordStatus_GUI.txt
    └── README_AD_UserPasswordStatus_GUI_EN.txt
```

## Requirements

- Windows 10/11 or Windows Server.
- PowerShell 5.1.
- Network/VPN access to Active Directory.
- AD PowerShell module / RSAT Active Directory tools.

If RSAT is missing, the script checks for it and can install:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

If elevation is required, the tool relaunches in an Administrator PowerShell window.

## First run

Run:

```text
Powershell 2026\AD-UserPasswordStatus-GUI\Start-AD-UserPasswordStatus-GUI.bat
```

Paste either the full script path or the folder containing the script.

Example:

```text
C:\Tools\Powershell 2026\AD-UserPasswordStatus-GUI
```

## Domain Controller setup

This clean version ships with an empty Domain Controller list.

Use one of these options:

1. Click `+` and add your DC hostname/FQDN, for example:

```text
DC01.example.local
```

2. Click `Discover DCs` and let the tool try to find DCs using AD/DNS.

Prefer hostnames/FQDNs over IP addresses. AD PowerShell cmdlets often rely on Kerberos/SSPI and may fail when the DC is entered as an IP address.

## Advanced Credentials

Advanced Credentials is intentionally not visible in the main UI.

Open it with:

```text
CTRL + SHIFT + click About
```

Available options:

- Set session credentials
- Save current credentials with Windows DPAPI
- Load saved credentials
- Forget saved credentials
- Test current credentials

The saved credential is stored for the current Windows user/profile only and is encrypted by Windows DPAPI.

Default clean-version credential path:

```text
%LOCALAPPDATA%\ADUserPasswordStatusGUI\ad-credential.xml
```

Do not commit this file to GitHub.

## GitHub install/update helper

Run:

```text
Powershell 2026\AD-UserPasswordStatus-GUI\Install-From-GitHub.bat
```

It will ask for:

- GitHub repo URL
- local project root folder, default:

```text
C:\Tools\Powershell 2026
```

The expected GitHub repository layout is:

```text
Powershell 2026
└── AD-UserPasswordStatus-GUI
```

If the project root is already a Git repo, it runs:

```text
git pull --ff-only
```

If the project root does not exist, it runs:

```text
git clone <repo-url> <project-root-folder>
```

For a private repository, GitHub may ask you to authenticate in a browser.

## Security notes

- Do not use a Domain Admin account unless absolutely necessary.
- Prefer a dedicated least-privilege AD account for reading user status and unlocking accounts.
- Never commit local config, credential files, logs, screenshots, or exported ZIP packages.
- `.gitignore` is included to reduce the chance of committing sensitive local files.
