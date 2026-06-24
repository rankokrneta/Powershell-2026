PROJECT STRUCTURE
=================

Powershell 2026 > AD-UserPasswordStatus-GUI

AD User Password / Lockout Check
Autor: Ranko Krneta
Verzija: 1.7.1-github-clean

NAMENA
------
Ovaj alat je mali Windows PowerShell GUI za proveru Active Directory password i lockout statusa korisnika.

GitHub-clean verzija nema hardkodovane domain controllere, domene, IP adrese, korisnike ili company-specific vrednosti.

FAJLOVI
-------
AD-UserPasswordStatus-GUI.ps1
Start-AD-UserPasswordStatus-GUI.bat
Install-From-GitHub.bat
README.md
README_AD_UserPasswordStatus_GUI.txt
README_AD_UserPasswordStatus_GUI_EN.txt
.gitignore

PREDUSLOVI
----------
- Windows 10/11 ili Windows Server
- PowerShell 5.1
- Network/VPN pristup Active Directory-ju
- RSAT Active Directory tools / ActiveDirectory PowerShell modul

Ako RSAT nije instaliran, skripta moze da ga instalira pomocu:

Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0

Ako su potrebna Administrator prava, skripta ce se sama relaunchovati elevated.

POKRETANJE
----------
Pokreni:

Start-AD-UserPasswordStatus-GUI.bat

Zatim nalepi punu putanju do AD-UserPasswordStatus-GUI.ps1 ili folder u kom se skripta nalazi.

Primer:

C:\Tools\Powershell 2026\AD-UserPasswordStatus-GUI

DOMAIN CONTROLLERS
------------------
Clean verzija startuje sa praznom listom Domain Controller-a.

Koristi + dugme da dodas svoj DC hostname/FQDN, na primer:

DC01.example.local

Ili klikni Discover DCs da alat pokusa da pronadje DC-eve preko AD/DNS-a.

Koristi hostname/FQDN kada god mozes. IP adrese mogu da izazovu SSPI/Kerberos greske sa AD PowerShell cmdletima.

ADVANCED CREDENTIALS
--------------------
Advanced Credentials nije vidljiv na glavnom UI-u.

Otvara se ovako:

CTRL + SHIFT + klik na About

Opcije:
- Set session credentials
- Save current credentials with Windows DPAPI
- Load saved credentials
- Forget saved credentials
- Test current credentials

Putanja za saved credential:

%LOCALAPPDATA%\ADUserPasswordStatusGUI\ad-credential.xml

Credential je enkriptovan preko Windows DPAPI i radi samo za istog Windows korisnika/profil na istom racunaru.

GITHUB INSTALLER
----------------
Pokreni:

Install-From-GitHub.bat

Pita za:
- GitHub repository URL
- lokalni install/update folder

Ako je folder vec Git repo, radi git pull --ff-only.
Ako folder ne postoji, radi git clone.

Za private GitHub repository, moguce je da ce traziti browser authentication.

NE COMMITOVATI
--------------
Ne commituj ove fajlove:
- AD-UserPasswordStatus-GUI.config.json
- ad-credential.xml
- *.clixml
- logove
- screenshotove
- exported ZIP pakete

SECURITY NAPOMENA
-----------------
Nemoj cuvati Domain Admin credentials osim ako bas nema sigurnije opcije.
Bolje koristi dedicated least-privilege AD nalog za ovaj alat.
