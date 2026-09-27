<p align="center">
  <img src="blockpulse-launcher.png" width="128" height="128" alt="blockpulse-launcher Logo">
</p>

# BlockPulse Aerocraft Launcher — platform layer and installer for Linux, macOS and BSD

![Unofficial](assets/unofficial-badge.svg)

> **This is an unofficial, community-made project.** It is not produced,
> reviewed, endorsed or supported by the BlockPulse / AeroCraft project. All
> trademarks and the game content belong to their respective owners.

The official BlockPulse Aerocraft launcher ships as compiled jars for Windows
only. This repository holds the **packaging** side of running it on Linux,
macOS and BSD:

- `blockpulse-launcher` — a runtime wrapper that finds a Java 21 runtime and
  JavaFX, probes the renderers and starts the launcher;
- `install.sh` — installer, uninstaller and package bookkeeping;
- `app/profiles/` — the modpack profile definitions the launcher expects.

**This repository contains no launcher source.** Neither the official backend
nor the platform layer is published here: no decompiled code, and no build for
either jar. Both artifacts are obtained separately, and the installer refuses to
run without them.

If you came here to build the launcher from source, this is the wrong
repository — there is nothing to build.

---

## What you need first

| File | Where it comes from |
|---|---|
| `app/Launcher.jar` | the official AeroCraft 0.6.2 distribution. Not built here, not redistributed here |
| `app/blockpulse-launcher-ui.jar` | the project's own release artifact. Not built here — the source is not published |

Drop both into `app/` before installing. The two jars are independent: the UI
reaches the backend through reflection
(`Class.forName("pro.gravit.launcher.core.api....")`), so they can be replaced
separately, and neither is signed by this project.

## Layout

```
app/
├── Launcher.jar                  official backend           (you supply)
├── blockpulse-launcher-ui.jar     front end + platform layer (you supply)
└── profiles/                     modpack profile definitions
assets/                           badge, icon
blockpulse-launcher               runtime wrapper
install.sh                        installer / uninstaller
```

`app/*.jar` is a supplied artifact and is not checked in.

There is nothing to build here. If you were looking for a source tree: this
repository is the packaging and installation side of the port, not the code.

## Install and run

```sh
./install.sh                  # install into ~/.local/share/BlockPulse
./install.sh --uninstall      # remove the launcher, the game, settings and logs
./install.sh --uninstall --keep-game
blockpulse-launcher           # run
blockpulse-launcher --diagnose
blockpulse-launcher --reset-graphics
```

`install.sh` refuses to install anything if the two jars are missing and prints
where to put them, rather than half-installing.

Supported package managers: **pacman** (Arch-based), **apt-get** (Debian-based)
and **dnf / dnf5 / microdnf** (Fedora, RHEL and their derivatives). The installer
only ever installs packages from the distribution's own repositories — it never
builds from source and never adds a third-party repository. If a package is
missing from them, it explains the options and stops instead of guessing.

### Removing

`--uninstall` deletes everything the launcher creates, and asks twice before
the irreversible part:

| What | Where |
|---|---|
| the launcher | `~/.local/share/BlockPulse` |
| the `blockpulse-launcher` command | `~/.local/bin` |
| desktop entry and icon | `~/.local/share/applications`, `~/.local/share/icons` |
| **Minecraft and every downloaded resource** | `~/.local/share/AeroCraft` (or `$XDG_DATA_HOME/AeroCraft`) |
| settings, remembered password file, graphics cache | `~/.config/blockpulse-launcher` |
| logs | `~/.local/state/blockpulse-launcher` |
| the remembered password in the system keyring | `secret-tool clear service com.blockpulse.aerocraft.launcher` |

The game directory is several GiB and cannot be recovered, so the size is
printed and a second confirmation is required. `--keep-game` removes everything
except the game.

`--uninstall-all` does the same and additionally removes the distribution
packages the installer added, together with the dependencies that only they
pulled in (`pacman -Rns` / `apt-get autoremove`). The installer records every
package it installs in `~/.local/state/blockpulse-launcher/installed-packages`;
only packages from that list are touched, so anything you installed yourself is
never removed. Installations made before this list existed have no record, and
`--uninstall-all` says so instead of guessing.

Configuration lives in `~/.config/blockpulse-launcher` (mode `0700`), logs in
`~/.local/state/blockpulse-launcher/launcher.log` with rotation at 5 MB.

### Runtime layout

| File | Role |
|---|---|
| `Launcher.jar` | backend; also put on the game classpath so the client can use `pro.gravit.launcher.core.api`. Its `Main-Class` is `pro.gravit.launcher.runtime.LauncherEngineWrapper`. |
| `blockpulse-launcher-ui.jar` | front end; main class `com.blockpulse.aerocraft.launcher.ui.AeroCraftLauncherUiApp` |
| `profiles/*.json` | modpack profiles |

`java -jar app/Launcher.jar` on its own is the backend, not an app: it starts
the launcher's console and the game runtime, which is what the official jar
does too. With no backend reachable it falls back to offline mode, prints

```
GravitLauncher (fork sashok724's Launcher) Launcher v5.7.9-1 stable
WARN JLine2 isn't in classpath, using std
ERROR Connection failed ... ConnectException
```

and exits. The official jar produces exactly the same output. The
"Модуль графического интерфейса лаунчера отсутствует" dialog comes from the
backend's fallback engine, which on Windows loads the JavaFX front end as a
signed module — this port starts the front end directly instead.

## What the platform layer changes

- **OS detection** — Windows, Linux, macOS, BSD (BSD shares the Linux path),
  with a safe fallback.
- **Install location per OS** — `%APPDATA%\AeroCraft` on Windows,
  `~/Library/Application Support/AeroCraft` on macOS,
  `$XDG_DATA_HOME/AeroCraft` or `~/.local/share/AeroCraft` on Linux/BSD.
- **Opening files, folders and links** — `xdg-open`, then `gio open`,
  `kde-open`, `gnome-open`; `open` on macOS.
- **Light/dark theme detection** — `GTK_THEME`, `gsettings`, `kreadconfig6` /
  `kreadconfig5`.
- **Finding a Java 21 runtime** — `JAVA_HOME`, `/usr/lib/jvm/*`, `~/.sdkman`,
  `~/.jdks`, JetBrains Toolbox, `PATH`.
- **LWJGL native libraries** — downloaded once from Maven Central
  (`org.lwjgl:<module>:<version>`), verified against the repository's `.sha1`,
  and only `*.so` entries are extracted (with a path-traversal check). A marker
  file prevents re-downloading. Linux only.
- **Launcher self-update** — skipped on non-Windows when the only available
  update is a Windows `.msi`; the launcher starts and shows an "update
  available" notice instead.
- **Remembered password** — can be stored in the desktop keyring via
  `secret-tool` instead of plain text in `launcher.properties`, migrating and
  deleting any existing plain-text copy. The prefs file is created with
  `rw-------` and written atomically.
- **Renderer probing** — the wrapper tries five JavaFX renderer presets
  (`prism.order=sw`, `prism.order=es2`, `LIBGL_ALWAYS_SOFTWARE=1`,
  `prism.forceGPU=false`, `-Djdk.gtk.version=2`) and caches the one that
  works. `BLOCKPULSE_NO_RETRY=1` disables it.

## Diagnostics

```sh
./blockpulse-launcher --diagnose
```

The smoke test is in the UI jar and runs headless:

```sh
FX=/usr/lib/jvm/java-21-openjdk/lib
java -Djava.awt.headless=true \
     --module-path "$(ls $FX/javafx.*.jar | tr '\n' ':')" \
     --add-modules javafx.controls,javafx.graphics \
     -cp app/blockpulse-launcher-ui.jar:app/Launcher.jar \
     com.blockpulse.aerocraft.launcher.ui.AeroCraftLauncherUiSmokeTest
```

Expected output:

```
[AeroCraftUiShell] Unavailable selected modpack fallback: aerocraft-full -> aerocraft-lite
[AeroCraftUiShell] Planned build ignored for launch: aerocraft-full
AeroCraft FXML-independent UI shell smoke test passed.
```

## Known limitations

- **The launcher does not update itself on Linux.** The update endpoint serves
  a Windows installer, so an update can only be reported, not applied. Manual
  replacement is required.
- **The reported version is still `0.6.2`** — the official
  `build-info.properties` is left untouched on purpose: bumping it would make
  the launcher demand an update it cannot install.
- **The modpack update channel is authenticated only by TLS.** The manifest and
  the archive it names are fetched over the same connection, and the SHA-256
  used to check the archive comes from that same manifest, so the checksum is
  not independent evidence of authenticity — whoever controls the channel can
  serve a matching pair. Plaintext endpoints are refused
  (`-Daerocraft.allowInsecureUpdateTransport=true` overrides for a local
  mirror), but a compromised CA or proxy is still enough. Pinning the update
  host, or signing the manifest, is the fix and is not implemented here.
- **The Windows self-updater does not verify the MSI signature.** It checks a
  SHA-256 that arrives in the same server response that named the URL, then
  runs `msiexec /i`. Plaintext installer URLs are refused; an Authenticode
  check is the real fix and needs a Windows host to implement and test. The
  path is dead code on Linux and macOS — `tryApply` returns `false` there.
- **The access token is passed to the game process in its command line.** That
  is what the Minecraft client expects, and on Linux `/proc/<pid>/cmdline` is
  readable only by the same user and root, so it is not a cross-user leak. The
  two credential files the platform layer writes —
  `config/aeroauth-autologin/account.json` (refresh token) and
  `~/.aerocraft/auth/session.json` (client ticket) — are created `0600` in the
  same filesystem call, so there is no window in which they are readable by
  anyone else, and the mode is re-applied on every write in case the file
  already existed with looser permissions.
- **Keyring requires a running secret service.** Without libsecret and a
  keyring daemon `secret-tool` fails and "remember me" silently turns itself
  off. There is no fallback yet, and it is Linux-only (macOS needs `security`).
- **`secret-tool` has an 8 second timeout**, so the first launch after a reboot
  can feel slow.
- **Modpack icon corners are square** on this port.
- **The installer does not build anything from the AUR.** If a distribution has
  no JavaFX package, `install.sh` says so and stops. It used to clone the
  current head of an AUR repository and run the PKGBUILD it found there, which
  meant executing instructions fetched over the network at install time from a
  repository this project does not control.
- **Fedora/RHEL is implemented but not run on real hardware.** `install.sh`
  detects `dnf`/`dnf5`/`microdnf`, installs and records the packages the same way
  it does for Arch and Debian, and removes them with `dnf remove` +
  `dnf autoremove`. The branch was verified against a simulated Fedora host with
  stubbed `dnf`/`rpm`/`sudo` — detection, the missing-dependency list, package
  installation, the JavaFX path and the uninstall path — but nobody has run the
  installer on an actual Fedora machine yet.
- **Not tested** on Debian/Ubuntu, NixOS, SteamOS, macOS or BSD.

## What is and is not in this repository

Contains: the wrapper, the installer, the badge and icon, and the modpack
profile definitions.

Does not contain, on purpose:

- **The official backend jar.** Obtain it from the project's own release
  channel. The launcher will not start without it and this project will not
  mirror it.
- **The platform layer's source.** `blockpulse-launcher-ui.jar` ships as a
  release artifact; its Java sources are not part of this repository.
- **Decompiled sources of the official launcher.** Nothing here was recovered
  by decompiling it. If you are the rights holder and want this taken down or
  relicensed, open an issue.
- **Any private key or credential.** The tree carries no signing key, no
  keystore and no token, and has no build step that could leak one. The official
  backend's own update-signing key is a property of the official binary — a key
  delivered to every client cannot be a secret, and the only real fix is a
  server-side protocol change.

## Legal

This repository is **not** affiliated with the BlockPulse / AeroCraft project.

This repository is licensed under the GNU GPL v3; the text is in
[`LICENCE`](LICENCE). It covers only the code in this repository, which is all
original work. All trademarks and the game content belong to their respective
owners.

Two things here are *not* covered by it, because they are not ours:

- `app/Launcher.jar` — not part of this repository, not redistributed by it.
  Anyone redistributing the official artifacts should make sure they have the
  rights to do so.
- `app/profiles/*.json` — the modpack profile definitions as they ship in the
  official distribution. Their terms are the project's.

The official launcher's own EULA applied to the official build. It does not
apply to this platform layer, which was written from scratch against the
backend's public API surface.
