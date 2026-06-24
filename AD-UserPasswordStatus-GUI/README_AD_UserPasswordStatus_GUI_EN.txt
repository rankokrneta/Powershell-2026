PROJECT STRUCTURE
=================

Powershell 2026 > AD-UserPasswordStatus-GUI

AD User Password / Lockout Check
Author: Ranko Krneta
Version: 1.7.1-github-clean

PURPOSE
-------
This tool is a small Windows PowerShell GUI for checking Active Directory user password and lockout status.

The GitHub-clean version contains no hardcoded domain controllers, domains, IP addresses, usernames, or company-specific values.

FILES
-----
AD-UserPasswordStatus-GUI.ps1
Start-AD-UserPasswordStatus-GUI.bat
Install-From-GitHub.bat
README.md
README_AD_UserPasswordStatus_GUI.txt
README_AD_UserPasswordStatus_GUI_EN.txt
.gitignore

REQUIREMENTS
------------
- Windows 10/11 or Windows Server
- PowerShell 5.1
- Network/VPN access to Active Directory
- RSAT Active Directory tools / ActiveDirectory PowerShell module

If RSAT is missing, the script can install it with:

Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

If Administrator elevation is needed, the script will relaunch itself elevated.

HOW TO START
------------
Run:

Start-AD-UserPasswordStatus-GUI.bat

Then paste either the full path to AD-UserPasswordStatus-GUI.ps1 or the folder where the script is located.

Example:

C:\Tools\Powershell 2026\AD-UserPasswordStatus-GUI

DOMAIN CONTROLLERS
------------------
The clean version starts with an empty Domain Controller list.

Use the + button to add your own DC hostname/FQDN, for example:

DC01.example.local

Or click Discover DCs to let the tool try to discover DCs using AD/DNS.

Use hostname/FQDN when possible. IP addresses can cause SSPI/Kerberos failures with AD PowerShell cmdlets.

ADVANCED CREDENTIALS
--------------------
Advanced Credentials is hidden from the main UI.

Open it with:

CTRL + SHIFT + click About

Available options:
- Set session credentials
- Save current credentials with Windows DPAPI
- Load saved credentials
- Forget saved credentials
- Test current credentials

Saved credential path:

%LOCALAPPDATA%\ADUserPasswordStatusGUI\ad-credential.xml

The saved credential is encrypted by Windows DPAPI and is usable only by the same Windows user/profile on the same PC.

GITHUB INSTALLER
----------------
Run:

Install-From-GitHub.bat

It asks for:
- GitHub repository URL
- Local install/update folder

If the target folder is already a Git repository, it runs git pull --ff-only.
If the folder does not exist, it runs git clone.

For a private GitHub repository, browser authentication may be required.

DO NOT COMMIT
-------------
Do not commit these files:
- AD-UserPasswordStatus-GUI.config.json
- ad-credential.xml
- *.clixml
- logs
- screenshots
- exported ZIP packages

SECURITY NOTE
-------------
Do not save Domain Admin credentials unless there is no safer option.
Prefer a dedicated least-privilege AD account for this tool.
