<p align="center">
  <img src="blockpulse-launcher.png" width="128" height="128" alt="blockpulse-launcher Logo">
</p>

# BlockPulse

![Unofficial](assets/unofficial-badge.svg)

> **This is an unofficial, community-made port.** It is not produced, reviewed,
> endorsed or supported by the BlockPulse / AeroCraft project. All trademarks
> and the game content belong to their respective owners.

The official BlockPulse Aerocraft launcher ships as compiled jars only. This
repository contains the **full decompiled source** of the official `0.6.2`
build, the platform layer added for Linux/macOS/BSD, and a reproducible build
that produces the same artifacts the launcher expects.

Everything here builds from source and behaves like the official build: same
class names, same binary names, same resources, same runtime behaviour. The
jars in `app/` are build outputs; they are not checked in.

---

## Layout

```
app/                          runtime artifacts
├── Launcher.jar              backend + GravitLaunch runtime      (build output)
├── blockpulse-launcher-ui.jar JavaFX front end                  (build output)
├── profiles/                 modpack profile definitions
└── decompilied/              the source project
    ├── pom.xml               parent POM (JDK 21, dependency management)
    ├── launcher-core/        backend, auth, update logic, game runtime
    ├── launcher-ui/          JavaFX front end
    ├── build.sh              build + stage the jars into app/
    ├── tools/                the scripts used to recover the source
    └── docs/                 provenance, class inventory, reading guide

blockpulse-launcher           runtime wrapper (Java/JavaFX discovery, graphics probing)
install.sh                    installer / uninstaller
```

`launcher-core` produces `Launcher.jar` and `launcher-ui` produces
`blockpulse-launcher-ui.jar`, matching the two runtime artifacts. The old
`blockpulse-launcher-secure-patch.jar` is gone: the two classes it used to
override (`LauncherPreferences`, `ModpackIconView`) are part of the source
tree now.

The two modules are independent on purpose. The UI talks to the backend
through reflection (`Class.forName("pro.gravit.launcher.core.api....")`), so it
compiles against nothing and the backend can be swapped without touching it.

## Build

Requirements: JDK 21+, Maven 3.9+.

```sh
./app/decompilied/build.sh      # generate key, build, sign, stage into app/
```

or directly:

```sh
cd app/decompilied && mvn -DskipTests package
```

Build output:

```
app/decompilied/launcher-core/target/Launcher.jar
app/decompilied/launcher-ui/target/blockpulse-launcher-ui.jar
```

The jars are copied into `app/`, where the wrapper and the installer pick them
up. `app/*.jar` is a build output and is not checked in.

### Entry points

**The GUI** is started by the wrapper, which is what `install.sh` links:

```sh
./blockpulse-launcher
```

**`Launcher.jar` on its own is the backend, not an app.** Running

```sh
java -jar app/Launcher.jar
```

starts the launcher's console and its game runtime, which is what the official
jar does too - it is a library for the game and for the UI, not a second front
end. With no backend reachable it falls back to offline mode, prints

```
GravitLauncher (fork sashok724's Launcher) Launcher v5.7.9-1 stable
WARN JLine2 isn't in classpath, using std
ERROR Connection failed ... ConnectException
```

and exits. The official jar produces exactly the same output. The
"Модуль графического интерфейса лаунчера отсутствует" dialog comes from
`pro.gravit.launcher.AeRocRAFtAOa3C`, the engine that the backend falls back to
when no GUI module is installed - on Windows the official build loads the JavaFX
front end as a signed module, and this port starts it directly instead.

### Code signing

The launcher refuses to start through its own entry point unless its classes
carry a valid code-signing chain, so `build.sh` signs `Launcher.jar` and pins
the certificate it signed with:

- on the first build an EC (secp256r1) key pair is generated in
  `~/.local/state/blockpulse-launcher/signing/launcher-signing.p12` (directory
  `0700`, files `0600`), never inside the project and never committed;
- its public certificate is written into the jar as
  `signing/trusted-codesign-certs.txt`, which the launcher reads at startup
  (`signing/official-codesign-certs.txt` is the committed copy of the official
  build's certificate, used when no local key is present);
- `Launcher.jar` is then signed with `jarsigner` (SHA384withECDSA). The
  keystore password is a random 32-character string generated on the machine and
  kept in a `0600` file; it is passed with `-storepass:file` so it never
  appears in the process arguments that `ps` can show to other users.

To sign with your own key instead:

```sh
BLOCKPULSE_SIGNING_KEYSTORE=/path/to/keystore.p12 \
BLOCKPULSE_SIGNING_ALIAS=myalias \
BLOCKPULSE_SIGNING_PASSWORD=secret \
./app/decompilied/build.sh
```

The certificate must carry the `codeSigning` EKU; the chain check rejects a
certificate without it.

### Dependencies

| Dependency | Version | Why |
|---|---|---|
| `net.java.dev.jna` + `jna-platform` | 5.17.0 | hardware/OS info for the secure checks |
| `com.github.oshi:oshi-core` | 6.12.0 | hardware inventory |
| `com.google.code.gson` | 2.13.1 | JSON |
| `org.slf4j` (api + simple) | 2.0.17 | logging |
| `org.openjfx:*` | 21.0.12 | UI, `provided` |
| `org.fusesource.jansi` | 2.4.1 | `provided`, optional at runtime |
| `org.jline:jline` | 3.29.0 | `provided`, optional at runtime |

`jansi` and `jline` are compile-time only. The official jars do not bundle
them either; the code probes for them at runtime
(`Class.forName("org.fusesource.jansi.Ansi")`) and falls back to plain output
and a line-based console, so runtime behaviour is unchanged.

JNA, OSHI, Gson and SLF4J are shaded into `Launcher.jar`, exactly as in the
official build.

## Install and run

```sh
./install.sh                  # install into ~/.local/share/BlockPulse
./install.sh --uninstall      # remove the launcher, the game, settings and logs
./install.sh --uninstall --keep-game
blockpulse-launcher           # run
blockpulse-launcher --diagnose
blockpulse-launcher --reset-graphics
```

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
package it installs in
`~/.local/state/blockpulse-launcher/installed-packages`; only packages from
that list are touched, so anything you installed yourself is never removed.
Installations made before this list existed have no record, and
`--uninstall-all` says so instead of guessing.

Configuration lives in `~/.config/blockpulse-launcher` (mode `0700`), logs in
`~/.local/state/blockpulse-launcher/launcher.log` with rotation at 5 MB.

### Runtime layout

| File | Role |
|---|---|
| `Launcher.jar` | backend; also put on the game classpath so the client can use `pro.gravit.launcher.core.api`. Its `Main-Class` is `pro.gravit.launcher.runtime.LauncherEngineWrapper`. |
| `blockpulse-launcher-ui.jar` | front end; main class `com.blockpulse.aerocraft.launcher.ui.AeroCraftLauncherUiApp` |
| `profiles/*.json` | modpack profiles |

## What was recovered from the jars

See [`app/decompilied/docs/decompilation-notes.md`](app/decompilied/docs/decompilation-notes.md)
for the full provenance, and
[`app/decompilied/docs/class-inventory.md`](app/decompilied/docs/class-inventory.md)
for the class map and a reading guide to the obfuscated package.

Short version:

- 541 first-party classes in `Launcher.jar` and 69 in the UI jar were
  decompiled and repaired until the whole tree compiled and the built-in
  smoke tests produced byte-identical output.
- 124 classes that the obfuscator had flattened to top level were put back
  into their enclosing class, using the `NestHost` / `NestMembers` /
  `InnerClasses` attributes that survived in the bytecode. Binary names
  (`Outer$Inner`) are unchanged.
- Eleven enums that CFR could not rebuild were reconstructed from the
  `<clinit>` constant names.
- `config.bin` (the signed launcher configuration) and the UI's
  `build-info.properties`, i18n bundles and `icon.png` are shipped
  byte-identical to the official jars.
- Third-party libraries were replaced with their Maven coordinates instead of
  being decompiled.

The obfuscated `pro.gravit.launcher` class names (`AeROCrAFTvxtw3` and friends)
are still the ones in the official jar. They were left alone on purpose:
renaming them changes the public surface that the game and any plugin talk to.
`app/decompilied/docs/class-inventory.md` lists what each one does.

## Platform changes on top of the official build

- **OS detection** — Windows, Linux, macOS, BSD (BSD shares the Linux path),
  with a safe fallback.
- **Install location per OS** — `%APPDATA%\AeroCraft` on Windows,
  `~/Library/Application Support/AeroCraft` on macOS,
  `$XDG_DATA_HOME/AeroCraft` or `~/.local/share/AeroCraft` on Linux/BSD.
- **Opening files, folders and links** — `xdg-open`, then `gio open`,
  `kde-open`, `gnome-open`; `open` on macOS; the previous Windows behaviour is
  unchanged.
- **Light/dark theme detection** — `GTK_THEME`, `gsettings`, `kreadconfig6` /
  `kreadconfig5`, and the Windows registry on Windows.
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

## Verifying a build

`build.sh` writes `app/BUILD-INFO.txt` next to the jars: build time, git commit,
the signing certificate's SHA-256 fingerprint, and the SHA-256 of both jars. To
check an archive or an install:

```sh
cd app
grep -A3 'sha256 of the artifacts' BUILD-INFO.txt
sha256sum -c <(grep -A3 'sha256 of the artifacts' BUILD-INFO.txt | tail -2)
```

A build is **not** byte-reproducible: `jarsigner` and the archive carry
timestamps, so two builds of the same commit differ. Compare against the
`BUILD-INFO.txt` of the archive you actually received, not against a hash
quoted somewhere else.

> **These are not the official jars.** The hashes published by the AeroCraft
> project (`1b08925d…` for `Launcher.jar`, `019c35b6…` for the UI jar,
> `e00840f7…` for `blockpulse-launcher-secure-patch.jar`) belong to the
> official Windows build. This port recompiles both jars from the source in
> this repository, so those hashes will never match, and
> `blockpulse-launcher-secure-patch.jar` no longer exists here at all - the two
> classes it used to override are part of the source tree. If you need the
> official artifacts, download them from the project's own release channel.

Diagnostics:

```sh
./blockpulse-launcher --diagnose
```

The built-in smoke tests are the closest thing to a regression check. They are
in the UI jar and run headless:

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
- **The update-check signing key is a client-side shared secret and must be
  treated as public.** The official build hard-codes one EC key pair and signs
  every `/updates/check` request with it, so anyone holding a copy of the
  launcher can produce a request the server accepts as the official client.
  Publishing the source does not create this weakness - the private key is in
  the distributed binary - but it does make it obvious that a private key
  delivered to every client cannot be a secret at all. The only real fix is a
  protocol change: nothing shared, a per-user non-exportable key held in the
  system keyring, or a challenge-response that proves freshness. The port makes
  the key replaceable so that change can be made without a rebuild: Put your own key pair in
  `~/.config/blockpulse-launcher/update-signing.properties`, mode 0600:

  ```properties
  privateKey=<base64 PKCS#8 EC private key>
  publicKey=<base64 X.509 SubjectPublicKeyInfo>
  ```

  or point `AEROCRAFT_LAUNCHER_UPDATE_SIGNING_KEY` (or the system property
  `aerocraft.launcher.updateSigningKey`) at that file. With no file present the
  built-in key is used, i.e. exactly the official behaviour. **Rotating it
  requires the server to accept the new public key.**
- **The modpack update channel is authenticated only by TLS.** The manifest and
  the archive it names are fetched over the same connection, and the SHA-256
  used to check the archive comes from that same manifest, so the checksum is
  not independent evidence of authenticity - whoever controls the channel can
  serve a matching pair. Plaintext endpoints are refused
  (`-Daerocraft.allowInsecureUpdateTransport=true` overrides for a local
  mirror), but a compromised CA or proxy is still enough. Pinning the update
  host, or signing the manifest, is the fix and is not implemented here.
- **The Windows self-updater does not verify the MSI signature.** It checks a
  SHA-256 that arrives in the same server response that named the URL, then
  runs `msiexec /i`. Plaintext installer URLs are now refused; an Authenticode
  check is the real fix and needs a Windows host to implement and test. The
  path is dead code on Linux and macOS - `tryApply` returns `false` there.
- **The access token is passed to the game process in its command line.** That
  is what the Minecraft client expects, and on Linux `/proc/<pid>/cmdline` is
  readable only by the same user and root, so it is not a cross-user leak. The
  two credential files this launcher writes -
  `config/aeroauth-autologin/account.json` (refresh token) and
  `~/.aerocraft/auth/session.json` (client ticket) - used to be created with
  the default `0644`, which is world-readable under the usual `umask 022`. Both
  are now created `0600` in the same filesystem call, so there is no window in
  which they are readable by anyone else, and the mode is re-applied on every
  write in case the file already existed with looser permissions.
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
- **Not tested** on Fedora, Debian/Ubuntu, NixOS, SteamOS, macOS or BSD.
- `Launcher.jar` is no longer byte-identical to the official jar; it is
  compiled from the source in this repository. See the decompilation notes for
  the fidelity report.

## Auditing for leaked secrets

`tools/scan_secrets.py` walks the working tree and every object in the git
object store (including unreachable blobs) and reports:

- PEM blocks of any kind;
- base64 constants that decode to a DER private key (PKCS#8 / SEC1) - this is
  what a hardcoded key looks like after decompilation;
- credential-shaped tokens (AWS, GitHub, GitLab, Slack, Google, JWT, Telegram);
- assignments that look like secrets, and key/keystore files.

```sh
python3 app/decompilied/tools/scan_secrets.py    # exit 0 = clean, 1 = unlisted key
```

Findings are printed once per distinct key, with the file it lives in, and
matched against `tools/secrets-allowlist.txt` - a checked-in list of
fingerprints (hashes, not keys) that are deliberately present, each with a
reason. Anything not on that list is a failure, so a newly added key cannot
pass unnoticed. The allowlist currently holds six fingerprints: the fixed EC update
key of the official build, its two public halves, the official build's
code-signing certificate, the certificate this build generates, and the stale
public certificate of a build from before the signing key was rotated.

Public keys and X.509 certificates are reported separately as `public`: they are
not secrets. Current state: one private key, the fixed EC update-signing key of
the official build, present in the distributed binary and rotatable as described
in [Known limitations](#known-limitations). No cloud, CI or chat tokens.

Exit codes: `0` clean, `1` unlisted key material, `2` the scan itself was
incomplete - a git object store that could not be read is never reported as
"clean".

The scanner has already earned its keep twice: it caught the code-signing
keystore that was being archived with the source, and it distinguishes a
private key from the public key that sits next to it - a naive "does it contain
a key" search flags both.

## Legal

This repository is **not** affiliated with the BlockPulse / AeroCraft project.

The project's own terms are in [`LICENCE`](LICENCE); they cover authorship of
the launcher and the conditions for modifying and redistributing it.

The source tree here was recovered by decompiling the official launcher's jars.
If you are the rights holder of that launcher, the licensing of the recovered
tree is yours to choose. Anyone redistributing it should make sure they have
the rights to do so. All trademarks and the game content belong to their
respective owners.

If you are the rights holder and want this taken down or relicensed, open an
issue or contact the maintainers.
