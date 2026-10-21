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
macOS and BSD — the runtime wrapper, the installer, the modpack profiles and
both jars, so a clone is ready to install:

- `blockpulse-launcher` — a runtime wrapper that finds a Java 21 runtime and
  JavaFX, reuses a cached renderer choice, seeds the game's memory setting and
  starts the launcher;
- `install.sh` — installer, uninstaller and package bookkeeping, with a
  Ukrainian / Russian / English interface and a quiet progress mode;
- `app/profiles/` — the modpack profile definitions the launcher expects,
  tuned with G1 flags for the game process.

**This repository contains no launcher source.** No decompiled code is
published here, and neither jar is built from source in this repository. Both
artifacts are included as-is so that a clone is ready to install.

If you came here to build the launcher from source, this is the wrong
repository — there is nothing to build.

## Versions

| What | Version |
|---|---|
| this port (installer, wrapper, profiles) | **1.0.0** |
| bundled BlockPulse launcher | **0.6.2** |

`./blockpulse-launcher --version` and `./install.sh --version` print both, so
the two are never confused in a bug report. The launcher's own
`build-info.properties` stays at `0.6.2` on purpose (see
[Known limitations](#known-limitations)); the port version changes with
packaging releases.

---

## Where to get the two jars

Both jars are checked in, so a clone is ready to install. If you would rather
download them directly:

| File | Size | SHA-256 |
|---|---|---|
| [`app/Launcher.jar`](https://github.com/Frosr1o2/BlockPulse-Aerocraft/raw/HEAD/app/Launcher.jar) | 5962532 B | `44d8bdcd978302ee2bdcfdeb042d974fbf267d5abe93206fbf2435e392240fbb` |
| [`app/blockpulse-launcher-ui.jar`](https://github.com/Frosr1o2/BlockPulse-Aerocraft/raw/HEAD/app/blockpulse-launcher-ui.jar) | 991708 B | `6bd3f5156dc34da109f4fd65b01a128f15b484d2abb60c9daa84bc30d7fcb92d` |

`Launcher.jar` is the official AeroCraft 0.6.2 backend, taken from the official
distribution and included here **unmodified** — it is not built from source, not
patched, and its own terms apply to it. The launcher verifies its code-signing
chain at startup, so an edited copy will not start; take it from the official
project if you prefer their current build rather than the pinned one here.
`blockpulse-launcher-ui.jar` is this project's own build and is unsigned.

Verify what you have before installing:

```sh
cd app
sha256sum -c <<'EOF'
44d8bdcd978302ee2bdcfdeb042d974fbf267d5abe93206fbf2435e392240fbb  Launcher.jar
6bd3f5156dc34da109f4fd65b01a128f15b484d2abb60c9daa84bc30d7fcb92d  blockpulse-launcher-ui.jar
EOF
```

then

```sh
cd .. && ./install.sh
```

The two jars are independent — the UI reaches the backend through reflection
(`Class.forName("pro.gravit.launcher.core.api....")`) — so either can be
replaced on its own.

## Layout

```
app/
├── Launcher.jar                  official backend, unmodified (checked in)
├── blockpulse-launcher-ui.jar     front end + platform layer   (checked in)
└── profiles/                     modpack profile definitions
assets/unofficial-badge.svg       the "unofficial" badge shown above
blockpulse-launcher               runtime wrapper
blockpulse-launcher.png           launcher icon
install.sh                        installer / uninstaller
```

If you were looking for a source tree: this repository is the packaging and
installation side of the port, not the code.

## Install and run

```sh
./install.sh                          # install into ~/.local/share/BlockPulse
./install.sh --quiet                  # the same, one progress line, no package-manager noise
./install.sh --lang uk                # interface language: uk, ru or en
./install.sh --yes                    # accept every prompt, for scripts
./install.sh --dry-run                # check the system only, change nothing
./install.sh --uninstall              # remove the launcher, the game, settings and logs
./install.sh --uninstall --keep-game  # the same, but keep Minecraft
./install.sh --uninstall-all          # also remove the packages the installer added
./install.sh --debug                  # verbose: what the package manager answered

blockpulse-launcher                   # run
blockpulse-launcher --version
blockpulse-launcher --diagnose
blockpulse-launcher --reset-graphics
blockpulse-launcher --quiet
```

`blockpulse-launcher --help` lists the wrapper's own flags and points at
`./install.sh --help` for the installer's, so the two never drift apart in the
documentation.

On the first run the installer asks for the interface language and remembers
it in `~/.config/blockpulse-launcher/language`; the wrapper reads the same file,
so the language chosen once stays chosen. `--lang uk|ru|en` and the
`BLOCKPULSE_LANG` environment variable override it without touching the
remembered value. This file controls the installer and the wrapper only — the
launcher window has its own language switch in the top bar.

There are three output modes. The default prints one line per step and keeps
the package-manager output in
`~/.local/state/blockpulse-launcher/install.log`, so the screen stays readable
when something fails. `--quiet` replaces the step lines with a single progress
bar (`[####----] 95%`) and needs a terminal; when the output is redirected it
falls back to `[2/4] 50%  copy files`. `--debug` streams everything live and is
the mode to use when reporting a packaging problem. `--help` prints every option
grouped by purpose (install, removal, output and language) together with
examples, and `--version` prints the port and launcher versions without
touching anything.

`install.sh` refuses to install anything if the two jars are missing and prints
where to put them, rather than half-installing. A missing `app/profiles/` set
does not stop the run, but it is reported even in quiet mode: the launcher would
start and then find no modpack.

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

Configuration lives in `~/.config/blockpulse-launcher` (mode `0700`): the
remembered language, `launcher.properties` with the launcher settings, and
`graphics-cache.sh` with the renderer combination that worked last time. Logs
live in `~/.local/state/blockpulse-launcher`: `launcher.log` for the wrapper
(rotation at 5 MB) and `install.log` for the installer (rotation at 2 MB).

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
  (default, `prism.order=sw`, `prism.order=es2` with `LIBGL_ALWAYS_SOFTWARE=1`,
  `prism.order=sw` plus `prism.forceGPU=false` with `LIBGL_ALWAYS_SOFTWARE=1`,
  and `-Djdk.gtk.version=2`) and caches the one that works
  in `~/.config/blockpulse-launcher/graphics-cache.sh`. Later starts use that
  cache first, so a working system pays no probing cost at all. The cache is
  written when the launcher exits, provided it either exited cleanly or had
  already stayed up for eight seconds, so a crash inside the game does not
  throw it away; it is discarded and rebuilt
  when the cached Java, its JavaFX jars or the native directory disappear, when
  `BLOCKPULSE_JAVA` points at another runtime, or when JavaFX itself fails to
  start. `BLOCKPULSE_NO_RETRY=1` disables the preset loop, and
  `BLOCKPULSE_MAX_PAIRS` (default 2) limits how many Java + JavaFX pairs are
  tried.
- **Fast start when the backend is down** — the UI requests its bootstrap
  document and news feed synchronously while building the window, each with a
  four-second timeout, and a server that accepts TCP but never answers stalls
  both. Before starting the JVM the wrapper sends one short request (0.6 s
  limit) to the bootstrap endpoint; if it does not answer, those calls are
  pointed at a refused local port for this launch and the window opens in about
  1.5 s instead of roughly 11 s. The negative result is remembered for ten
  minutes, so repeated starts pay nothing extra, and the next probe restores
  normal behaviour as soon as the backend answers again. `BLOCKPULSE_ONLINE=1`
  turns the probe off and `BLOCKPULSE_PROBE_TIMEOUT` changes its limit.

### Memory and the game's JVM

On the first start the wrapper writes `ramGb` into
`~/.config/blockpulse-launcher/launcher.properties`, but only when the key is
absent: 55% of installed RAM, clamped to 2–12 GiB. The launcher's settings
screen reads the same key, so a value chosen there wins and is never
overwritten. `BLOCKPULSE_RAM_GB=6 blockpulse-launcher` seeds a different value
on a fresh profile.

All five profile definitions carry Aikar-style G1 flags in `jvmArgs`
(`UseG1GC`, `MaxGCPauseMillis=200`, the G1 size and region percentages,
`PerfDisableSharedMem`). The launcher appends them after the `-Xmx` it computes
from the memory setting. `AlwaysPreTouch` is deliberately absent: it trades a
slower start for steadier ticks, and fast start is what this layer optimises.

## Diagnostics

```sh
./blockpulse-launcher --diagnose    # java, javafx, packages, natives
./install.sh --debug                # installer: what apt/dnf/pacman answered
```

`--debug` is only interesting when the installer says a package is missing. It
prints the candidate list it probed and what the package manager reports, which
distinguishes "no such package in this release" from "the package lists have
not been populated yet".

The smoke test is in the UI jar and runs headless. On Arch JavaFX is the
separate `java21-openjfx` package, which unpacks into the JDK's own library
directory (`/usr/lib/jvm/java-21-openjdk/lib` here). On Debian and Fedora run
`./blockpulse-launcher --diagnose` first and take the directory it prints under
"javafx lib dirs found" (on Debian that is usually `/usr/share/openjfx/lib`).

```sh
FX=/usr/lib/jvm/java-21-openjdk/lib     # Arch
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
- **The bundled launcher still reports `0.6.2`** — `build-info.properties` is
  deliberately left at the official version: bumping it would make the launcher
  demand an update it cannot install. The port's own version is separate and
  changes with packaging releases (see [Versions](#versions)).
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
- **Fedora/RHEL support is newer than the rest and thinner than the rest.**
  `install.sh` detects `dnf`/`dnf5`/`microdnf`, installs and records packages the
  same way it does for Arch and Debian, and removes them with `dnf remove` +
  `dnf autoremove`. JavaFX is found by asking `rpm` where `javafx.controls.jar`
  actually landed, because Fedora 41+ ships it as the standalone `openjfx`
  package in a `lib64` path that none of the fixed directories match. A first run
  inside a Fedora 44 VM exposed three real bugs, all fixed: the installer named
  a package that does not exist on Fedora, its JavaFX search never matched rpm's
  output format, and the wrapper told every non-Debian system to run `pacman`.
  Those fixes are verified against the real command output formats, but the
  end-to-end run on Fedora has not been repeated yet.
- **The Debian branch probes for a package instead of assuming one.**
  `openjdk-21-jre` does not exist on Ubuntu 22.04, which the Mint 21 series is
  built on, and Mint ships its own `msopenjdk-21` build. The installer asks
  `apt-cache policy` for a real candidate and names whichever it finds;
  when there is none it explains that a PPA is the user's decision rather than
  adding one. JavaFX has the same treatment (`openjfx`, `libopenjfx-java`,
  `openjfx-swt`). Note that `openjfx` on older releases is JavaFX 11 and will
  not load on a Java 21 runtime — the wrapper's version-mismatch message covers
  that case. A first run inside a Linux Mint 22.3 live session found the package
  probing correct but also showed that a failing `apt-get update` — the usual
  cause being the installer CD-ROM in a live session's sources — used to kill
  the installer with no message at all. Package manager failures are now
  reported per command and the run continues, and the package probe falls back
  to `apt-cache show` when `apt-cache policy` reports no candidate, which is
  what a live session does before its lists are populated. That case is now
  handled at the source: `apt_update` builds a temporary source list with the
  `deb cdrom:` entry removed and updates through that, so the live ISO's
  installer disc cannot stop the package lists from being written, while the
  system's own `sources.list` is left untouched. When a package still cannot be
  found the installer prints what `apt-cache` answers instead of only asserting
  that nothing is available. A live Mint 22.3 run then installed `openjdk-21-jre`
  and `openjfx` successfully — the Debian path works — but exposed the next
  problem: **Ubuntu 24.04 and Mint 22 package JavaFX as version 11**, while the
  launcher is built against JavaFX 21. The installer used to print
  "Java/JavaFX: готово" whenever a jar with the right name existed, which was
  simply false. It now resolves the module and reports the version, warning when
  it is older than 21. Getting JavaFX 21 on Ubuntu 24.04 means a distribution
  that has it (Debian 13 and newer) or SDKMAN/coursier; the installer will not
  add a PPA on its own. In practice the mismatch turned out not to be fatal: on
  Mint 22.3 the launcher **did start and run** on the distribution's JavaFX 11
  with a Java 21 runtime. Read the warning as "this combination is outside what
  was tested", not as "it does not work" - the installer prints the version it
  found either way.

> **Installing from a live session does not persist.** The live ISO runs in RAM,
> so `/home`, the launcher and the installed packages are gone on reboot. Use it
> to test the installer, then install again from a real system — or install the
> distribution to disk first. The same applies to a live USB stick.
- **Not tested** on NixOS, SteamOS, macOS or BSD.

## What is and is not in this repository

Contains: the wrapper, the installer, the badge and icon, the modpack profile
definitions, and both runtime jars.

Does not contain, on purpose:

- **Launcher source.** Neither jar is built from source here; the launcher
  cannot be rebuilt from this repository.
- **The platform layer's source.** `blockpulse-launcher-ui.jar` is checked in
  as a binary; its Java sources are not part of this repository.
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

The code in this repository — the wrapper, the installer, the badge, the icon —
is licensed under the MIT licence; the text is in [`LICENSE`](LICENSE). All
trademarks and the game content belong to their respective owners.

Two things here are *not* covered by it, because they are not ours and MIT
cannot relicense somebody else's work:

- `app/Launcher.jar` — the official AeroCraft backend, included unmodified, not
  patched. The official project's own terms govern it. If you are its rights
  holder and want it gone, open an issue.
- `app/profiles/*.json` — the modpack profile definitions as they ship in the
  official distribution. The project's terms govern those too.

The official launcher's own EULA applied to the official build. It does not
apply to this platform layer, which was written from scratch against the
backend's public API surface.
