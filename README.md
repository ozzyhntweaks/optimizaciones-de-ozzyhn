<p align="center"><img src="assets/ozzyhn-pfp-512.png" width="160" alt="OZZYHN TWEAKS"></p>

# OPTIMIZACIONES DE OZZYHN

**by OZZYHN TWEAKS** · [github.com/ozzyhntweaks](https://github.com/ozzyhntweaks) · **English / Español**

**A hardware-aware Windows 10 / 11 optimizer with a futuristic neon interface.**
It scans the PC, works out what kind of machine it is, and tunes Windows for *that* machine. That holds whether it is a $150 Celeron laptop that needs reviving or an RTX 4090 rig chasing every frame.

Every switch shows the **real state read from Windows right now**, every change is **logged and reversible**, and the whole thing is one open-source PowerShell file you can read before you run it. The interface switches between **English and Spanish** with one click (EN | ES in the title bar), and starts in Spanish on Spanish Windows.

---

## Launch

Open **PowerShell as Administrator** and paste:

```powershell
irm https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1 | iex
```

This always runs the latest **release**, which GitHub Actions checks, hashes and publishes. Changes on the `main` branch never reach you until they are released.

> **Only use this address** (or the [Releases page](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases)). Copies posted anywhere else (other sites, video descriptions, Discord, forks) are not mine and may contain malware.

Or download **`Run-Ozzyhn.cmd`** from the [latest release](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest) and double-click it (it asks for admin rights by itself).
On older Windows 10 builds, if the download fails, use this longer command:

```powershell
[Net.ServicePointManager]::SecurityProtocol='Tls12'; irm https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1 | iex
```

**Requirements:** Windows 10 (1809+) or Windows 11, x64 or ARM64, administrator account. Nothing to install: it uses the PowerShell built into Windows.

### Check your copy (optional)

Every release includes `SHA256SUMS.txt` and a GitHub build attestation, which proves the file was built from this repository by GitHub Actions and not changed afterwards. Download `ozzyhn.ps1` from the [latest release](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest), then run:

```powershell
Get-FileHash .\ozzyhn.ps1 -Algorithm SHA256
```

The hash must match the line for `ozzyhn.ps1` in `SHA256SUMS.txt` (upper or lower case does not matter). If you have the [GitHub CLI](https://cli.github.com), you can also check the attestation:

```powershell
gh attestation verify .\ozzyhn.ps1 --repo ozzyhntweaks/optimizaciones-de-ozzyhn
```

Then start the file you checked from PowerShell as Administrator: `powershell -ExecutionPolicy Bypass -File .\ozzyhn.ps1`

---

## What it does

| Tab | What you get |
|---|---|
| **Dashboard** | CPU-Z-style spec sheet (CPU, cores and cache, GPU and VRAM, RAM type, speed and channels, drives, board, BIOS, battery wear, VBS/HVCI, Secure Boot, TPM). Live CPU load, real clock speed, RAM, temperature and uptime. **OZ Score** and tier: **CHEAP / BUDGET / MID-RANGE / FANCY**. Smart insights such as an HDD system drive, single-channel RAM, XMP probably off, old GPU driver, too many startup apps, or a hot laptop. |
| **Tweaks** | **169 tweaks in 15 categories**. Each one detects its own state, so the switches show what is actually active. Flip what you want, then apply. Search, filters, *Recommended for this PC* badges and risk labels (Safe, Moderate, Advanced, Danger). |
| **Games** | Apex Legends, Fortnite, Counter-Strike 2, VALORANT, Overwatch 2 and Rainbow Six Siege X. Finds each game and its launcher, shows its icon, reads its own video settings file and shows what to change, lists the competitive menu settings for *this* PC and gives the launch options to copy for Steam, EA app or Epic. Game files are never changed. |
| **Themes** | Desktop themes for [Rainmeter](https://www.rainmeter.net): a big clock in five styles (Horizon, Blade, Stack, Pulse, Minimal) that **picks its text color from the part of the wallpaper under it**, a status bar (date, time, CPU, RAM, network, volume, battery), a dock with your installed apps and a wallpaper picker with slanted cards and color filters. Five looks, nine positions, sizes for any screen scaling, English and Spanish, a live preview, six original wallpapers drawn by the app, and **REMOVE THEME** to take it all away. |
| **Profiles** | One click, resolved for this PC: **Auto-Tune**, **Revive Cheap PC**, **Max Performance**, **Cool & Quiet**, **Competitive Gaming**, **Privacy Max**, **Clean Windows UI**. *Preview* stages the changes for review; *Apply* does it now. |
| **Debloat** | Lists only the bloat that is actually installed (66 known packages), with recommended ones pre-selected. Core apps (Store, Calculator, Notepad, Terminal, Security) are protected and never shown. Also includes the official Edge uninstall where Microsoft allows it. |
| **Drivers** | Official download links for the detected NVIDIA / AMD / Intel GPU, the chipset, the laptop or board maker and the network adapter. It also lists devices with missing drivers and the age of key drivers, and links to NVCleanstall and DDU for clean GPU installs. |
| **Tools** | **Clean up files**: pick the drives, scan, see each item with its size and folders, and tick what to delete (recommended items come ticked). DISM component cleanup, DISM + SFC repair, network stack reset, disk scan, DNS switcher (Cloudflare, Google, Quad9, AdGuard), three custom power plans, battery report, CompactOS for tiny eMMC drives, a startup app manager and shortcuts to the classic panels. |
| **Backup & Undo** | Automatic System Restore point, an **undo journal** that records the original value of everything changed, one-click revert per tweak or *Revert everything*, and export or import of your setup. |

### Tweak categories

Privacy & Telemetry (19), AI & Copilot (8), Performance (14), Gaming & Input (11), Power & Thermals (8), Services (15), Network & Latency (9), Explorer & UI (27), Start, Taskbar & Search (16), Edge, OneDrive & Store (7), Installed Apps (3), Windows Update (7), Storage & NTFS (7), Security Hardening (13), Danger Zone (5).

Tweaks for hardware or apps you do not have stay hidden: the Bluetooth and fingerprint services only show up on PCs without that hardware, and the Chrome, Firefox and Office switches only when that app is installed.

### Fast **and** cool

Three power plans are built to keep idle temperatures low:

* **OZZYHN PERFORMANCE**: aggressive boost and unparked cores under load, but a 5% minimum CPU state so the CPU idles cool. PCIe, USB and disk power saving are off while plugged in.
* **OZZYHN SMART**: efficient-aggressive boost. Close to full speed when you need it, with much less heat and noise the rest of the time. The default for laptops.
* **OZZYHN COOL**: turbo off. The rescue plan for laptops that overheat.

Undervolting and BIOS settings (XMP / EXPO, fan curves) cannot be changed safely from Windows. The app tells you when they are worth doing instead of pretending.

---

## Safety

* A **System Restore point** is created before changes (you can turn this off).
* The **original value of every registry key, service and task is saved** before it is touched, in `C:\ProgramData\Ozzyhn\journal.json`.
* **Danger Zone** settings (Defender real-time, SmartScreen, Memory Integrity, VBS, CPU mitigations) are **never part of any profile** and always ask for confirmation.
* Hardware-specific tweaks hide themselves where they do not apply: laptop-only, desktop-only, Windows 11-only, NVIDIA/AMD-only and VMs.
* No telemetry, no ads, no downloads of other tools. Logs stay in `C:\ProgramData\Ozzyhn\logs`.
* **THEMES** never downloads or installs Rainmeter: it opens the official site and you install it yourself. Rainmeter is always started as you, not as administrator, so dock clicks and the skins' own scripts never get admin rights, and the app never runs those scripts itself. It only writes inside `Rainmeter\Skins\OZZYHN` (and `Pictures\OZZYHN Wallpapers` when you ask for wallpapers), refuses to write through junctions or symbolic links, and REMOVE THEME deletes only that skins folder.
* The data folder `C:\ProgramData\Ozzyhn` is **locked so only administrators can change it**. Otherwise another program without admin rights could plant an undo journal and get the app to apply it with admin rights.
* Every change to the code is checked automatically for downloads, `Invoke-Expression`, antivirus exclusions and PSScriptAnalyzer security rules before it can be released. See [SECURITY.md](SECURITY.md) to report a problem privately.

> Use at your own risk. This tool changes system settings. Read what a switch does before you flip it.

---

## FAQ

**Will it break Windows Update?** No. Updates are never disabled. There are optional switches to delay feature updates, stop auto-restarts or skip driver updates.

**Do I need Rainmeter for the THEMES page?** Yes. Rainmeter is a free, open-source desktop customization tool. Press GET RAINMETER on the THEMES page to open its official site, install it, then press CHECK AGAIN. You can set the theme up and see the preview before installing it.

**Can I undo everything?** Yes. Use *Backup & Undo → Revert everything*, or turn individual switches back off. Removed apps can be reinstalled from the Microsoft Store.

**Why is my temperature "N/A"?** Many motherboards hide their sensors from Windows. Use HWiNFO for exact readings. Everything else still works.

**Can cleaning delete my own files or other drives?** No. *Clean up files* only lists Windows cache folders on the Windows drive (usually C:) and the Recycle Bin of the drives you pick. Nothing is deleted until you tick it and confirm, links are never followed, and your own files are never listed.

**Does it work in Spanish (or any language) Windows?** Yes. All detection is language-independent.

---

## What's new

**1.4.1:** fix: **CREATE OZZYHN WALLPAPERS** said "Theme failed" with no reason even though the wallpapers were made; it now adds the folder and opens it. **1.4.0:** new **THEMES** page (Rainmeter clock that matches your wallpaper, status bar, dock, wallpaper picker, original wallpapers) and **40 new tweaks** (AI in Paint and Notepad, laptop standby, hardware-aware services, Chrome / Firefox / Office telemetry, security hardening, update control, Explorer and right-click menu cleanup). **1.3.0:** **Clean up files** replaces Quick clean: pick drives, scan, and choose exactly what to delete, with sizes and folders shown and recommended items pre-ticked. **1.2.1:** important fix: **Quick clean** no longer follows links to other drives, only empties the Windows drive's Recycle Bin, and asks before it starts. **1.2.0:** new **Games** page (competitive settings, settings-file check and launch options for six shooters), the window fits small laptop screens, neon pop-ups, a results card after applying, and Ctrl+F search. **1.1.2:** the double-click launcher always runs the newest release, and every tweak is tested on real Windows (apply, check, revert, check) before each release. **1.1.1:** security fix for the data folder, and launching from Releases. Full history in [CHANGELOG.md](CHANGELOG.md).

---

## Source

Everything is in one file, `ozzyhn.ps1`. The logo and profile picture are in `/assets` (SVG source + PNG). Releases are published by [`.github/workflows/release.yml`](.github/workflows/release.yml) when the version number in `ozzyhn.ps1` changes, using that version's section of [CHANGELOG.md](CHANGELOG.md) as release notes.

---

## En español

**Optimizaciones de Ozzyhn** (por **OZZYHN TWEAKS**) analiza tu PC (CPU, GPU, RAM, disco, placa y batería) y detecta si es de escritorio o portátil, si usa Windows 10 u 11 y si es una PC **barata, económica, de gama media o de gama alta**. Luego la optimiza según ese resultado. Cada interruptor muestra el estado real de Windows y todo se puede deshacer. La app está **en español y en inglés**: cambia con el botón **EN | ES** de la barra de título.

La página **Temas** crea temas de escritorio para Rainmeter: un reloj en cinco estilos que elige el color del texto según la parte del fondo que tiene debajo, una barra de estado, un dock con tus apps y un selector de fondos con filtros de color. La app nunca descarga Rainmeter: te lleva al sitio oficial. Todo se quita con **QUITAR TEMA**.

La página **Juegos** revisa Apex Legends, Fortnite, Counter-Strike 2, VALORANT, Overwatch 2 y Rainbow Six Siege X: detecta el juego y su launcher, lee su archivo de ajustes de video para decirte qué cambiar, muestra los ajustes competitivos para tu PC y te da las opciones de lanzamiento para copiar. Nunca modifica los archivos de tus juegos.

Ábrelo en **PowerShell como administrador**:

```powershell
irm https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1 | iex
```

Descárgalo **solo** desde esta dirección o desde la página de [Releases](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases). Las copias publicadas en otros sitios no son mías y pueden tener malware. Cada versión incluye `SHA256SUMS.txt` para comprobar tu copia con `Get-FileHash`.

---

MIT License. Made by **OZZYHN TWEAKS** · [github.com/ozzyhntweaks](https://github.com/ozzyhntweaks)
