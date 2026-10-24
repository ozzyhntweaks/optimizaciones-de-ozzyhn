# Security policy

## Get it only from here

Optimizaciones de Ozzyhn is published in one place: the [Releases page](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases) of this repository. The launch command in the README downloads from there:

```powershell
irm https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1 | iex
```

Copies on other websites, in video descriptions, on Discord or in forks are not official and may have been changed to include malware.

## Check a download

Each release is built by GitHub Actions from a version tag ([release.yml](.github/workflows/release.yml)) and includes:

* `SHA256SUMS.txt`: compare it with `Get-FileHash .\ozzyhn.ps1 -Algorithm SHA256`.
* A GitHub build attestation: `gh attestation verify .\ozzyhn.ps1 --repo ozzyhntweaks/optimizaciones-de-ozzyhn` confirms the file was built from this repository and not changed afterwards.

## What the tool never does

* Download or run other programs or scripts from the internet.
* Add antivirus exclusions.
* Disable Windows Update.
* Turn off Defender real-time protection, SmartScreen, Memory Integrity, VBS or CPU mitigations, unless you pick that Danger Zone switch yourself and confirm it. Danger Zone switches are never part of a profile.

Every push and every release runs [check-script.ps1](.github/scripts/check-script.ps1), which fails if the script gains a download command, `Invoke-Expression`, a Defender exclusion, non-ASCII characters or a PSScriptAnalyzer security finding. [test-datadir.ps1](.github/scripts/test-datadir.ps1) checks on a real Windows machine that the data folder (`C:\ProgramData\Ozzyhn`) stays locked to administrators.

## Supported versions

Only the latest release receives security fixes.

## Report a vulnerability

Please do not open a public issue. Use **Security > Report a vulnerability** on this repository, which reaches the maintainer privately. Include the app version, your Windows version and the steps to reproduce.

---

## En español

Descárgalo solo desde la página de [Releases](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases) o con el comando del README. Cada versión incluye `SHA256SUMS.txt` y una atestación de compilación de GitHub para comprobar tu copia. Para reportar un problema de seguridad, usa **Security > Report a vulnerability** en este repositorio (es privado), no un issue público.
