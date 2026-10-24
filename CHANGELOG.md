# Changelog

Each release on the [Releases page](https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases) uses its section below as release notes. To release: add a section for the new version at the top, set `$Oz.Version` in `ozzyhn.ps1` to match, and push to `main`.

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
