# Changelog

Each release on the [Releases page](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases) uses its section below as release notes. To release: add a section for the new version at the top, set `$Oz.Version` in `ozzyhn.ps1` to match, and push to `main`.

## 1.2.0

* **New GAMES page** for Apex Legends, Fortnite, Counter-Strike 2, VALORANT, Overwatch 2 and Rainbow Six Siege X:
  * Finds each game and the launcher it came from (Steam, EA app, Epic, Battle.net, Ubisoft Connect, Riot Client), and shows the game's own icon from your PC.
  * Reads the game's own video settings file (Apex `videoconfig.txt`, Fortnite `GameUserSettings.ini`, CS2 `cs2_video.txt`) and shows which settings already match the competitive setup and which to change.
  * Lists what to set in each game's menu, adjusted to your PC (GPU maker, video memory, laptop or desktop, screen refresh rate).
  * Gives the launch options for your launcher with a COPY button and the exact place to paste them (for example `-dev +fps_max 0` for Apex). Where a game has no useful launch options, it says so instead of listing placebo ones.
  * Game files are never changed.
* **Fits small screens.** The window sizes itself to the screen it opens on, so 1366x768 laptops at 125% scaling see the whole app. On short screens the menu hides its two bottom cards so every page button fits.
* **New-style pop-ups.** Confirmations use the app's neon look instead of plain Windows boxes.
* **Results card** after applying several changes: how many worked, any that failed or that Windows kept off, tweaks active before and after, and a restart button when needed.
* **Ctrl+F** jumps to the tweak search from any page; Esc clears it.
* The PowerShell window behind the app is minimized while the app is open, and comes back when you close it.
* Every release is now tested by opening the real app on Windows: every page at normal and small-laptop size, in English and Spanish, plus the dialogs. Any error, or any text without a Spanish translation, blocks the release.

## 1.1.2

* **The double-click launcher always gets the newest version.** `Run-Ozzyhn.cmd` now downloads the latest release first, and only uses the `ozzyhn.ps1` next to it when there is no internet. Before, anyone who had both files kept running their old copy forever.
* **Fix: settings Windows protects no longer break a tweak.** *Diagnostic services OFF* (part of *Revive Cheap PC* on PCs under 8 GB) stopped halfway on a service Windows does not let anyone change, and *Revert* stopped on the same one. Protected settings are now skipped and logged, like protected tasks already were, and revert always restores everything else.
* **Every tweak is tested on real Windows before release.** Each registry, service and task tweak is applied, checked to read ON, reverted, and checked that every original value came back exactly.
* Bug report form that asks for the version, Windows build and log.

## 1.1.1

* **Security fix.** The data folder `C:\ProgramData\Ozzyhn` could be written by any account on the PC. A program without admin rights could plant an undo journal there, and *Revert* would then apply it with admin rights. The folder is now locked to administrators. Your undo journal is carried over if an administrator wrote it; otherwise the old folder is set aside without being read.
* The launch command downloads the latest release instead of the `main` branch.
* Releases are published by GitHub Actions with `SHA256SUMS.txt` and a build attestation, after automatic checks for downloads, `Invoke-Expression` and antivirus exclusions.

## 1.1.0

* Registry tweaks really apply. 1.0 deleted registry values instead of writing them, so switches showed ON while nothing changed. If you used 1.0, press **RE-APPLY** on the Tweaks page.
* Tweaks with nothing to change on your PC show **N/A** and are not counted. Anything Windows blocks or later undoes is flagged with a one-click re-apply.
* Faster scan and background tasks, smooth scrolling in the tweak list.
* English / Español switch, the new OZ logo.

## 1.0.0

* First release.
