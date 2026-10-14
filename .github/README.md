<div align="center">
    <h1>shizuka</h1>
    <h3>Hyprland dotfiles, running the <b>shizuka</b> (静か) Quickshell shell</h3>
</div>

<div align="center">

![last-commit](https://img.shields.io/github/last-commit/kayano-tatsuya/shizuka?style=for-the-badge&color=8ad7eb&logo=git&logoColor=D9E0EE&labelColor=1E202B)
![stars](https://img.shields.io/github/stars/kayano-tatsuya/shizuka?style=for-the-badge&logo=andela&color=86dbd7&logoColor=D9E0EE&labelColor=1E202B)
![repo-size](https://img.shields.io/github/repo-size/kayano-tatsuya/shizuka?color=86dbce&label=SIZE&logo=protondrive&style=for-the-badge&logoColor=D9E0EE&labelColor=1E202B)

</div>

## What this is

A Hyprland dotfiles config whose shell is **shizuka** — a Quickshell/QML desktop shell
providing the bar, wallpaper selector, sidebar, notifications, lock screen, overlays
and a large pile of settings.

- Configuration files, plus a Quickshell shell.
- **Not** a system provisioning script: no GPU drivers, no zram, no bootloader.
- Targets Arch and Fedora-based systems. Other distros are best-effort.

## Install

```bash
git clone https://github.com/kayano-tatsuya/shizuka.git
cd shizuka
./setup install
```

The installer refuses to run as root. It symlinks `dots/` and `dots-extra/` into
`~/.config` and installs the shell to `~/.config/quickshell/shizuka`.

To uninstall, remove the symlinks and the shell directory.

## Layout

| Path | Purpose |
|---|---|
| `dots/.config/quickshell/shizuka/` | The shizuka shell (QML). This is the bulk of the repo. |
| `dots/.config/hypr/hyprland/` | Hyprland config: `variables.lua`, `execs.lua`, `keybinds.lua` |
| `dots-extra/` | Optional per-distro extras (e.g. Fedora) |
| `sdata/` | Installer logic and packaging recipes |
| `setup` | Installer entrypoint |

Shell settings and user data live outside the repo, in `~/.config/shizuka/`
(`config.json`, `presets/`, `actions/`). The repo holds defaults only.

## Notes on this fork

- The shell config directory, the QML module namespace, and the launch variable
  were renamed from their upstream names to **shizuka**, so the config does not
  advertise itself as a fork. Where behaviour depended on the old names, it was
  updated: the `panelFamily` setting, the `qs -c` re-activation path, and the
  `QUICKSHELL_CONFIG_NAME` used by the wallpaper and theme scripts.
- The **secret-tool keyring namespace is deliberately unchanged.** The stored
  Gemini API key is filed under the original application attribute; renaming it
  would orphan the stored secret. Only the user-visible label was rebranded.
- The Settings → About "Update" button clones this repository and extracts
  `dots/.config/quickshell/shizuka/`, so it updates the shell in place.

## Credits

This work is a derivative and would not exist without the following. Both are
worth reading if you want a maintained or more general-purpose version:

- **[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)** — the
  original Hyprland dotfiles and the Quickshell shell lineage, under the GPL-3.0
  (see `LICENSE`).
- **[pctrade/end4-pC](https://github.com/pctrade/end4-pC)** — the Quickshell
  shell this was adopted from, and the source of the wallpaper/booru services.

The wallpaper selector, booru sidebar, and shell services in particular are
end-4's and pctrade's work. This repository is a rebrand plus local changes, not
a from-scratch shell. the authors of the respective dots above deserve their share of credit due, if you like this work, check them out as well.

## Support

If you like this, you can support me here:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/kayanotatsuya)

## 寄付・サポート

気に入っていただけましたら、こちらからサポートしていただけると嬉しいです：

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/kayanotatsuya)
