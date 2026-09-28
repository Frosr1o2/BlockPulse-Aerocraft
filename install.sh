#!/usr/bin/env bash
set -euo pipefail

VERSION=0.6.2
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
# Under sudo the home of the invoking user is the interesting one; otherwise a
# caller who overrides HOME (tests, containers, a second profile) must get the
# paths they asked for instead of the ones in passwd.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && command -v getent >/dev/null 2>&1; then
    INSTALL_HOME="$(getent passwd "$INSTALL_USER" | cut -d: -f6 || true)"
else
    INSTALL_HOME="${HOME:-}"
fi
INSTALL_HOME="${INSTALL_HOME:-$HOME}"
DATA_DIR="$INSTALL_HOME/.local/share"
INSTALL_DIR="${BLOCKPULSE_INSTALL_DIR:-$DATA_DIR/BlockPulse}"
BIN_DIR="$INSTALL_HOME/.local/bin"
APP_DIR="$INSTALL_DIR/app"
DESKTOP_DIR="$DATA_DIR/applications"
ICON_DIR="$DATA_DIR/icons/hicolor/256x256/apps"
DESKTOP_FILE="$DESKTOP_DIR/blockpulse-launcher.desktop"
ICON_FILE="$ICON_DIR/blockpulse-launcher.png"
LINK_FILE="$BIN_DIR/blockpulse-launcher"

# what the launcher itself creates at runtime, see LauncherPaths/PlatformSupport
XDG_DATA_DIR="${XDG_DATA_HOME:-}"
[ -n "$XDG_DATA_DIR" ] && [ "${XDG_DATA_DIR#/}" = "$XDG_DATA_DIR" ] && XDG_DATA_DIR=""
XDG_DATA_DIR="${XDG_DATA_DIR:-$INSTALL_HOME/.local/share}"
CONF_DIR="${XDG_CONFIG_HOME:-$INSTALL_HOME/.config}/blockpulse-launcher"
STATE_DIR="${XDG_STATE_HOME:-$INSTALL_HOME/.local/state}/blockpulse-launcher"
GAME_DIR="$XDG_DATA_DIR/AeroCraft"
PACKAGE_LIST="$STATE_DIR/installed-packages"
SECRET_SERVICE="com.blockpulse.aerocraft.launcher"

say() { printf '%s\n' "$*"; }
ask() {
    local prompt="$1" answer
    read -r -p "$prompt" answer
    case "${answer:-Y}" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}
has() { command -v "$1" >/dev/null 2>&1; }
root_run() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}
user_run() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$INSTALL_USER" -H "$@"
    else
        "$@"
    fi
}
chown_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown -R "$INSTALL_USER:$(id -gn "$INSTALL_USER")" "$@"
    fi
}
java21_path() {
    local c major out
    local -a candidates=()
    [ -n "${BLOCKPULSE_JAVA:-}" ] && candidates+=("$BLOCKPULSE_JAVA")
    [ -n "${JAVA_HOME:-}" ] && candidates+=("$JAVA_HOME/bin/java")
    while IFS= read -r c; do candidates+=("$c"); done < <(printf '%s\n' /usr/lib/jvm/*/bin/java 2>/dev/null | sort -rV)
    c="$(command -v java 2>/dev/null || true)"
    [ -n "$c" ] && candidates+=("$c")
    for c in "${candidates[@]}"; do
        [ -x "$c" ] || continue
        out="$("$c" -version 2>&1 || true)"
        major="$(printf '%s\n' "$out" | sed -n '1s/.*version "\([0-9]*\).*/\1/p')"
        [ -n "$major" ] && [ "$major" -ge 21 ] 2>/dev/null && { printf '%s\n' "$c"; return 0; }
    done
    return 1
}
javafx_path() {
    local c java_path
    java_path="$(java21_path 2>/dev/null || true)"
    if [ -n "$java_path" ] && "$java_path" --list-modules 2>/dev/null | grep -q '^javafx.controls@'; then
        printf '%s\n' bundled
        return 0
    fi
    for c in \
        /usr/share/openjfx/lib \
        /usr/lib/openjfx/lib \
        /usr/lib64/openjfx/lib \
        /usr/share/openjfx/lib64 \
        /usr/share/java/openjfx/lib \
        /usr/lib/jvm/*openjfx*/lib \
        /usr/lib/jvm/*/lib \
        /usr/lib64/jvm/*/lib; do
        [ -f "$c/javafx.controls.jar" ] && { printf '%s\n' "$c"; return 0; }
    done
    # Fedora and other rpm distros keep the versioned JavaFX packages, so ask
    # rpm where the jar actually landed instead of guessing a path.
    if rpm_installed_any openjfx java-21-openjfx java-22-openjfx java-23-openjfx; then
        local found
        found="$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | grep -ixE 'openjfx|java-[0-9]+-openjfx' \
            | while IFS= read -r pkg; do rpm -ql "$pkg" 2>/dev/null; done \
            | awk -F/ '$NF == "javafx.controls.jar" {print $0}' | head -1)"
        if [ -n "$found" ] && [ -f "$found" ]; then
            printf '%s\n' "$(dirname "$found")"
            return 0
        fi
    fi
    return 1
}
package_manager() {
    if has pacman; then
        printf '%s\n' arch
    elif has apt-get; then
        printf '%s\n' debian
    elif has dnf || has dnf5 || has microdnf; then
        printf '%s\n' fedora
    else
        printf '%s\n' unsupported
    fi
}
dnf_cmd() {
    if has dnf5; then
        printf '%s\n' dnf5
    elif has dnf; then
        printf '%s\n' dnf
    else
        printf '%s\n' microdnf
    fi
}
rpm_installed() {
    has rpm || return 1
    rpm -q "$1" >/dev/null 2>&1
}
# Fedora ships a runtime under several names depending on the release, and the
# versioned name changes with every JDK bump, so accept any of them.
rpm_installed_any() {
    local candidate
    for candidate in "$@"; do
        rpm_installed "$candidate" && return 0
    done
    return 1
}
missing_dependencies() {
    local manager="$1"
    DEP_MISSING=()
    case "$manager" in
        arch)
            if ! java21_path >/dev/null 2>&1 && ! pacman -Qq jdk21-openjdk >/dev/null 2>&1 && ! pacman -Qq jre21-openjdk >/dev/null 2>&1; then
                DEP_MISSING+=(jdk21-openjdk)
            fi
            javafx_path >/dev/null 2>&1 || DEP_MISSING+=(java21-openjfx)
            has xdg-open || DEP_MISSING+=(xdg-utils)
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                pacman -Qq xorg-xwayland >/dev/null 2>&1 || DEP_MISSING+=(xorg-xwayland)
            fi
            has secret-tool || DEP_MISSING+=(libsecret)
            ;;
        debian)
            if ! java21_path >/dev/null 2>&1; then
                DEP_MISSING+=("$(debian_java_package || printf '%s\n' openjdk-21-jre)")
            fi
            if ! javafx_path >/dev/null 2>&1; then
                DEP_MISSING+=("$(debian_javafx_package || printf '%s\n' openjfx)")
            fi
            has xdg-open || DEP_MISSING+=(xdg-utils)
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                dpkg -s xwayland >/dev/null 2>&1 || DEP_MISSING+=(xwayland)
            fi
            has secret-tool || DEP_MISSING+=(libsecret-tools)
            ;;
        fedora)
            if ! java21_path >/dev/null 2>&1 && ! rpm_installed_any java-21-openjdk java-21-openjdk-headless java-1.21.0-openjdk; then
                DEP_MISSING+=(java-21-openjdk)
            fi
            if ! javafx_path >/dev/null 2>&1; then
                # name the package dnf can actually install, not one that only
                # exists in some other distribution
                DEP_MISSING+=("$(fedora_javafx_package || printf '%s\n' openjfx)")
            fi
            has xdg-open || DEP_MISSING+=(xdg-utils)
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                rpm_installed xorg-x11-server-Xwayland || DEP_MISSING+=(xorg-x11-server-Xwayland)
            fi
            has secret-tool || DEP_MISSING+=(libsecret)
            ;;
    esac
}
install_arch_javafx() {
    if pacman -Si java21-openjfx >/dev/null 2>&1; then
        try_root_run pacman -S --needed --noconfirm java21-openjfx
        return 0
    fi
    if has paru; then
        paru -S --needed --noconfirm java21-openjfx
        return 0
    fi
    if has yay; then
        yay -S --needed --noconfirm java21-openjfx
        return 0
    fi
    # No AUR fallback on purpose. Cloning the current head and running its
    # PKGBUILD means executing instructions fetched over the network at install
    # time from a repository this project does not control. If the distro has
    # no JavaFX package, the user has to pick one deliberately.
    say ""
    say "В этом репозитории нет пакета с JavaFX, а сборка из AUR отключена:"
    say "установщик не выполняет PKGBUILD, скачанный из сети."
    say "Варианты:"
    say "  * Arch с multilib:  sudo pacman -S java21-openjfx   (обычно есть в extra)"
    say "  * другой дистрибутив / репозиторий с JavaFX 21"
    say "  * указать JAVA_HOME и JAVAFX_LIB вручную (см. README)"
    debian_explain_missing "openjfx"
    return 1
}
# Fedora ships JavaFX either as a per-JDK package or, from Fedora 41+, as a
# standalone openjfx. Returns the name that is actually available so the
# "missing dependency" message names a package dnf can install.
fedora_javafx_package() {
    local dnf pkg
    dnf="$(dnf_cmd)"
    for pkg in java-21-openjfx openjfx; do
        rpm_installed "$pkg" && { printf '%s\n' "$pkg"; return 0; }
        "$dnf" -q list --available "$pkg" >/dev/null 2>&1 && { printf '%s\n' "$pkg"; return 0; }
    done
    return 1
}
install_fedora_javafx() {
    local dnf pkg
    dnf="$(dnf_cmd)"
    # JavaFX ships per JDK version on Fedora, so the package name follows the
    # runtime. Nothing is built from source and nothing is pulled from a
    # third-party repository: if the matching package is missing, the user
    # chooses the path deliberately.
    if pkg="$(fedora_javafx_package)"; then
        if ! try_root_run "$dnf" install -y "$pkg"; then
            return 1
        fi
        record_package "$pkg"
        return 0
    fi
    say ""
    say "В репозиториях нет JavaFX для Java 21, и установщик не берёт его из"
    say "сторонних источников: подключать репозиторий — решение пользователя."
    say "Варианты:"
    say "  * sudo dnf install openjfx             (Fedora 41+, JavaFX отдельным пакетом)"
    say "  * sudo dnf install java-21-openjfx     (Fedora 40 и старше, JavaFX на каждый JDK)"
    say "  * другой дистрибутив / репозиторий с JavaFX 21"
    say "  * указать JAVA_HOME и JAVAFX_LIB вручную (см. README)"
    return 1
}
# A package manager that fails must not take the whole installer down: under
# `set -e` a non-zero exit killed the script with no message at all, so the user
# never learned that a single broken source or package was the cause.
# "JavaFX: готово" used to mean "a jar with that name exists". On Ubuntu 24.04
# the distro package is JavaFX 11, which is not what the launcher was built
# against, so the check now resolves the module and reports its version.
javafx_status() {
    local java_path fx_dir line version major
    java_path="$(java21_path 2>/dev/null || true)"
    if [ -z "$java_path" ]; then
        printf '%s
' "нет Java 21"
        return 1
    fi
    fx_dir="$(javafx_path 2>/dev/null || true)"
    if [ -z "$fx_dir" ]; then
        printf '%s
' "нет JavaFX"
        return 1
    fi
    if [ "$fx_dir" = bundled ]; then
        line="$("$java_path" --list-modules 2>/dev/null | grep -E '^javafx\.controls@' | head -1)"
    else
        # Only the javafx jars: the same directory also holds jrt-fs.jar, which
        # collides with the jrt.fs module of the JDK itself and makes the boot
        # layer fail to initialise.
        fx_path=""
        for jar in "$fx_dir"/javafx.*.jar; do
            [ -f "$jar" ] || continue
            case "$jar" in
                */javafx.base.jar|*/javafx.controls.jar|*/javafx.fxml.jar|*/javafx.graphics.jar|*/javafx.media.jar|*/javafx.swing.jar|*/javafx.web.jar)
                    fx_path="${fx_path:+$fx_path:}$jar"
                    ;;
            esac
        done
        if [ -n "$fx_path" ]; then
            line="$("$java_path" --module-path "$fx_path" --describe-module javafx.controls 2>/dev/null | head -1)"
        fi
    fi
    [ -n "$line" ] || { printf '%s
' "JavaFX не загружается этой средой"; return 1; }
    version="$(printf '%s\n' "$line" | sed -n 's/.*@\([0-9][0-9.]*\).*/\1/p')"
    [ -n "$version" ] || version="неизвестна"
    major="$(printf '%s\n' "$version" | cut -d. -f1)"
    case "$major" in
        ''|*[!0-9]*) ;;
        *) [ "$major" -ge 21 ] 2>/dev/null && { printf 'JavaFX %s\n' "$version"; return 0; } ;;
    esac
    printf 'JavaFX %s (нужен 21 или новее)\n' "$version"
    return 1
}
try_root_run() {
    if root_run "$@"; then
        return 0
    fi
    say ""
    say "Не удалось выполнить: $*"
    return 1
}
# A live session lists the installer CD-ROM in sources.list. apt-get update then
# fails on it and writes no package lists at all, so every later apt-cache query
# behaves as if nothing were installed. Filtering that one source out for the
# duration of this command is enough: the system is not modified, the child
# process simply does not see the broken entry.
apt_update() {
    local tmp rc
    tmp="$(mktemp 2>/dev/null || true)"
    if [ -n "$tmp" ]; then
        { grep -rhvE '^[[:space:]]*deb(-src)?[[:space:]]+cdrom:' \
                 /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true; } >"$tmp"
    fi
    if [ -n "$tmp" ] && [ -s "$tmp" ]; then
        root_run apt-get update \
            -o "Dir::Etc::sourcelist=$tmp" \
            -o "Dir::Etc::sourceparts=/dev/null" \
            -o "APT::Get::List-Cleanup=0"
        rc=$?
        rm -f "$tmp"
        return $rc
    fi
    [ -n "$tmp" ] && rm -f "$tmp"
    root_run apt-get update
}
# Ubuntu 22.04 (and the Mint 21 series built on it) has no openjdk-21 at all,
# and Mint ships its own msopenjdk build, so the package name has to be probed
# rather than assumed. apt-cache prints "Candidate: (none)" for a known but
# unavailable package and "Unable to locate package" for an unknown one, so
# matching a real candidate is the reliable test.
debian_package_available() {
    dpkg -s "$1" >/dev/null 2>&1 && return 0
    has apt-cache || return 1
    # "policy" is the precise answer, "show" covers a cache state where policy
    # prints no candidate line at all but the package is in the index.
    apt-cache policy "$1" 2>/dev/null | grep -qE "^[[:space:]]*Candidate: [^(]" && return 0
    apt-cache show "$1" >/dev/null 2>&1
}
# When nothing is found, the reason matters more than the verdict: on a live
# session the package lists start out stale, and "no such package" and "no
# candidate yet" look identical from the outside.
debian_explain_missing() {
    [ "$DEBUG" = 1 ] || return 0
    say ""
    say "Что отвечает apt про первый кандидат ($1):"
    if has apt-cache; then
        apt-cache policy "$1" 2>&1 | sed -n '1,6p' | while IFS= read -r line; do say "  $line"; done
        say "Файлы индексов: $(ls /var/lib/apt/lists/*Packages* 2>/dev/null | wc -l)"
    fi
}
debian_java_package() {
    local pkg
    for pkg in openjdk-21-jre msopenjdk-21 openjdk-21-jdk openjdk-21-jre-headless; do
        debian_package_available "$pkg" && { printf '%s\n' "$pkg"; return 0; }
    done
    return 1
}
debian_javafx_package() {
    local pkg
    for pkg in openjfx libopenjfx-java openjfx-swt; do
        debian_package_available "$pkg" && { printf '%s\n' "$pkg"; return 0; }
    done
    return 1
}
install_debian_javafx() {
    local pkg
    if pkg="$(debian_javafx_package)"; then
        if ! try_root_run apt-get install -y "$pkg"; then
            return 1
        fi
        record_package "$pkg"
        return 0
    fi
    say ""
    say "В репозиториях нет пакета с JavaFX, и установщик не подключает"
    say "сторонние PPA: решение остаётся за пользователем."
    say "Варианты:"
    say "  * sudo apt-get install openjfx"
    say "    (!) В Ubuntu 24.04 и Mint 22 этот пакет — JavaFX 11, сборке нужен 21."
    say "      JavaFX 21 есть в Debian 13 и новее, либо его ставят через SDKMAN/coursier."
    say "  * указать JAVA_HOME и JAVAFX_LIB вручную (см. README)"
    return 1
}
install_dependencies() {
    local manager="$1" java_pkg
    case "$manager" in
        arch)
            if ! pacman -Qq jdk21-openjdk >/dev/null 2>&1 && ! pacman -Qq jre21-openjdk >/dev/null 2>&1; then
                try_root_run pacman -S --needed --noconfirm jdk21-openjdk && record_package jdk21-openjdk
            fi
            if ! pacman -Qq xdg-utils >/dev/null 2>&1; then
                try_root_run pacman -S --needed --noconfirm xdg-utils && record_package xdg-utils
            fi
            if ! javafx_path >/dev/null 2>&1; then
                # || true: под 'set -e' непустой return оборвал бы установку до
                # итоговой проверки missing_dependencies ниже
                install_arch_javafx || true
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                if ! pacman -Qq xorg-xwayland >/dev/null 2>&1; then
                    try_root_run pacman -S --needed --noconfirm xorg-xwayland && record_package xorg-xwayland
                fi
            fi
            if ! pacman -Qq libsecret >/dev/null 2>&1; then
                try_root_run pacman -S --needed --noconfirm libsecret && record_package libsecret
            fi
            ;;
        debian)
            if ! apt_update; then
                say ""
                say "apt-get update завершился с ошибкой даже без CD-источника."
                say "Пробую поставить с текущими индексами; если пакет не найден,"
                say "ниже будет показано, что отвечает про него apt."
            fi
            if ! java21_path >/dev/null 2>&1; then
                if java_pkg="$(debian_java_package)"; then
                    try_root_run apt-get install -y "$java_pkg" && record_package "$java_pkg"
                else
                    say ""
                    say "В репозиториях нет Java 21, и установщик не подключает"
                    say "сторонние PPA. На Ubuntu 22.04 и Mint 21 его нет вовсе:"
                    say "  * перейти на Ubuntu 24.04 / Mint 22 и новее"
                    say "  * либо указать JAVA_HOME вручную (см. README)"
                    debian_explain_missing "openjdk-21-jre"
                fi
            fi
            if ! javafx_path >/dev/null 2>&1; then
                install_debian_javafx || true
            fi
            if ! dpkg -s xdg-utils >/dev/null 2>&1; then
                try_root_run apt-get install -y xdg-utils && record_package xdg-utils
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                if ! dpkg -s xwayland >/dev/null 2>&1; then
                    try_root_run apt-get install -y xwayland && record_package xwayland
                fi
            fi
            if ! dpkg -s libsecret-tools >/dev/null 2>&1; then
                try_root_run apt-get install -y libsecret-tools && record_package libsecret-tools
            fi
            ;;
        fedora)
            local dnf
            dnf="$(dnf_cmd)"
            if ! java21_path >/dev/null 2>&1 && ! rpm_installed_any java-21-openjdk java-21-openjdk-headless java-1.21.0-openjdk; then
                try_root_run "$dnf" install -y java-21-openjdk && record_package java-21-openjdk
            fi
            if ! javafx_path >/dev/null 2>&1; then
                install_fedora_javafx || true
            fi
            if ! has xdg-open && ! rpm_installed xdg-utils; then
                try_root_run "$dnf" install -y xdg-utils && record_package xdg-utils
            fi
            if { [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; } && ! rpm_installed xorg-x11-server-Xwayland; then
                try_root_run "$dnf" install -y xorg-x11-server-Xwayland && record_package xorg-x11-server-Xwayland
            fi
            if ! has secret-tool && ! rpm_installed libsecret; then
                try_root_run "$dnf" install -y libsecret && record_package libsecret
            fi
            ;;
    esac
}
record_package() {
    mkdir -p "$STATE_DIR"
    if [ -f "$PACKAGE_LIST" ] && grep -qxF "$1" "$PACKAGE_LIST"; then
        return 0
    fi
    printf '%s\n' "$1" >>"$PACKAGE_LIST"
}
write_desktop() {
    mkdir -p "$DESKTOP_DIR" "$ICON_DIR"
    install -Dm644 "$BASE_DIR/blockpulse-launcher.png" "$ICON_FILE"
    cat > "$DESKTOP_FILE" <<EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=BlockPulse Launcher
GenericName=Minecraft Launcher
Comment=BlockPulse Launcher
Exec=$INSTALL_DIR/blockpulse-launcher
TryExec=$INSTALL_DIR/blockpulse-launcher
Icon=blockpulse-launcher
Terminal=false
Categories=Game;
Keywords=Minecraft;BlockPulse;Launcher;
StartupWMClass=com.blockpulse.aerocraft.launcher.ui.AeroCraftLauncherUiApp
EOF_DESKTOP
    chmod 644 "$DESKTOP_FILE"
    if has update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi
    if has gtk-update-icon-cache; then
        gtk-update-icon-cache -f -t "$DATA_DIR/icons/hicolor" >/dev/null 2>&1 || true
    fi
}
remove_desktop() {
    rm -f "$DESKTOP_FILE" "$ICON_FILE"
    if [ -d "$DESKTOP_DIR" ] && has update-desktop-database; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi
}
human_size() {
    local bytes
    bytes="$(du -sb "$1" 2>/dev/null | cut -f1)" || bytes=""
    [ -z "$bytes" ] && { printf '?'; return 0; }
    awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ");
        i = 1;
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i];
    }'
}
remove_path() {
    local path="$1" what="$2"
    [ -e "$path" ] || return 0
    [ -n "$path" ] && [ "$path" != "/" ] && [ "$path" != "$INSTALL_HOME" ] || {
        say "Пропуск $path: небезопасный путь."
        return 0
    }
    say "  удаляю $what: $path ($(human_size "$path"))"
    rm -rf "$path"
}
clear_keyring() {
    has secret-tool || return 0
    if secret-tool lookup service "$SECRET_SERVICE" account x >/dev/null 2>&1; then
        say "  удаляю сохранённый пароль из связки ключей"
        secret-tool clear service "$SECRET_SERVICE" >/dev/null 2>&1 || true
    fi
}
uninstall_launcher() {
    local keep_game="$1"
    say "Удаление BlockPulse Launcher"
    if [ -d "$INSTALL_DIR" ] || [ -e "$GAME_DIR" ] || [ -e "$CONF_DIR" ]; then
        say "Будет удалено:"
        say "  программа:        $INSTALL_DIR"
        [ "$keep_game" = 0 ] && say "  игра и ресурсы:   $GAME_DIR ($(human_size "$GAME_DIR"))"
        say "  настройки:        $CONF_DIR"
        say "  логи:             $STATE_DIR"
        say "  пароль в связке ключей (secret-tool, служба $SECRET_SERVICE)"
        ask "Удалить лаунчер, настройки и логи? [y/N] " || { say "Отменено."; return 0; }
    else
        say "Ничего не найдено, удалять нечего."
    fi

    if [ "$keep_game" = 0 ] && [ -e "$GAME_DIR" ]; then
        say ""
        say "ВНИМАНИЕ: вместе с лаунчером будет безвозвратно удалён Minecraft"
        say "         и все скачанные ресурсы ($GAME_DIR, $(human_size "$GAME_DIR"))."
        ask "         Удалить игру тоже? [y/N] " || { say "Игра оставлена."; keep_game=1; }
    fi

    remove_path "$INSTALL_DIR" "программу"
    rm -f "$LINK_FILE"
    remove_desktop
    rmdir "$BIN_DIR" 2>/dev/null || true

    if [ "$keep_game" = 0 ]; then
        remove_path "$GAME_DIR" "игру"
    else
        say "  оставляю игру: $GAME_DIR"
    fi
    clear_keyring
    remove_path "$CONF_DIR" "настройки"
    remove_path "$STATE_DIR" "логи"
    say "BlockPulse Launcher удалён."
}
uninstall_dependencies() {
    [ -f "$PACKAGE_LIST" ] || { say "Список установленных пакетов не найден: $PACKAGE_LIST"; return 0; }
    local manager packages present
    manager="$(package_manager)"
    packages="$(grep -v '^[[:space:]]*$' "$PACKAGE_LIST")"
    [ -n "$packages" ] || { say "Зависимости не устанавливались этой программой."; return 0; }

    present=""
    for pkg in $packages; do
        case "$manager" in
            arch) pacman -Qq "$pkg" >/dev/null 2>&1 && present="$present $pkg" ;;
            debian) dpkg -s "$pkg" >/dev/null 2>&1 && present="$present $pkg" ;;
            fedora) rpm_installed "$pkg" && present="$present $pkg" ;;
        esac
    done
    present="${present# }"
    [ -n "$present" ] || { say "Установленных пакетов не найдено."; rm -f "$PACKAGE_LIST"; return 0; }

    say "Будут удалены пакеты, которые поставил установщик:$present"
    say "(-Rns / autoremove: уйдут и зависимости, которые нужны только им)"
    ask "Удалить? [y/N] " || { say "Отменено."; return 0; }
    case "$manager" in
        arch) root_run pacman -Rns --noconfirm $present ;;
        debian) root_run apt-get remove -y $present; root_run apt-get autoremove -y ;;
        fedora)
            root_run "$(dnf_cmd)" remove -y $present
            root_run "$(dnf_cmd)" autoremove -y
            ;;
    esac
    rm -f "$PACKAGE_LIST"
    say "Зависимости удалены."
}
require_artifacts() {
    local missing=0
    for artifact in Launcher.jar blockpulse-launcher-ui.jar; do
        if [ ! -f "$BASE_DIR/app/$artifact" ]; then
            say "Не найден app/$artifact"
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        cat <<EOF_MISSING

Оба файла лежат в репозитории в app/. Похоже, копия неполная.
Возьми их оттуда:
  https://github.com/Frosr1o2/BlockPulse-Aerocraft

или положи оба файла в:
  $BASE_DIR/app/

и запусти установку снова.
EOF_MISSING
        return 1
    fi
    if [ ! -d "$BASE_DIR/app/profiles" ] || [ -z "$(find "$BASE_DIR/app/profiles" -maxdepth 1 -type f -name '*.json' -print -quit)" ]; then
        say "В app/profiles нет ни одного профиля - установка продолжится без них."
    fi
}

install_launcher() {
    local manager="$1"
    require_artifacts || exit 1
    mkdir -p "$APP_DIR" "$APP_DIR/profiles" "$BIN_DIR"
    install -Dm644 "$BASE_DIR/app/Launcher.jar" "$APP_DIR/Launcher.jar"
    install -Dm644 "$BASE_DIR/app/blockpulse-launcher-ui.jar" "$APP_DIR/blockpulse-launcher-ui.jar"
    find "$BASE_DIR/app/profiles" -maxdepth 1 -type f -name '*.json' -exec install -Dm644 {} "$APP_DIR/profiles/" \;
    install -Dm755 "$BASE_DIR/blockpulse-launcher" "$INSTALL_DIR/blockpulse-launcher"
    rm -rf "$INSTALL_DIR/decompiled" "$INSTALL_DIR/patch" "$INSTALL_DIR/packaging" "$INSTALL_DIR/.git"
    rm -f "$INSTALL_DIR/README.md" "$INSTALL_DIR/PKGBUILD" "$INSTALL_DIR/build.sh" "$INSTALL_DIR/run.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/BUILD_LINUX.md" "$INSTALL_DIR/BUILD_TAB_FIX.txt" "$INSTALL_DIR/blockpulse-launcher.png"
    chown_user "$INSTALL_DIR"
    if ask "Добавить команду blockpulse-launcher в ~/.local/bin? [Y/n] "; then
        ln -sfn "$INSTALL_DIR/blockpulse-launcher" "$LINK_FILE"
        chown_user "$LINK_FILE"
    else
        rm -f "$LINK_FILE"
    fi
    if ask "Добавить BlockPulse в меню приложений, Fuzzel, Wofi, Rofi и другие XDG-лаунчеры? [Y/n] "; then
        write_desktop
        chown_user "$DESKTOP_DIR" "$ICON_DIR"
    else
        remove_desktop
    fi
    say "Установлено: $INSTALL_DIR"
    say "Версия: $VERSION"
    javafx_note=""
    if javafx_status >/tmp/.blockpulse-javafx-status 2>/dev/null; then
        javafx_note="Java/JavaFX: готово — $(cat /tmp/.blockpulse-javafx-status)"
    else
        javafx_note="Java/JavaFX: $(cat /tmp/.blockpulse-javafx-status 2>/dev/null || echo 'не готово')"
    fi
    rm -f /tmp/.blockpulse-javafx-status
    say "$javafx_note"
    case "$javafx_note" in
        *"нужен 21"*)
            say ""
            say "Пакет JavaFX в этом дистрибутиве старее, чем требует сборка."
            say "Установщик не подключает сторонние PPA: решение за вами."
            say "Варианты:"
            say "  * дистрибутив с JavaFX 21 (Debian 13 и новее)"
            say "  * SDKMAN или coursier: готовый JavaFX 21 рядом с Java 21"
            say "  * ./blockpulse-launcher --diagnose - покажет, грузится ли модуль"
            ;;
    esac
    if [ -L "$LINK_FILE" ]; then
        say "Команда: $LINK_FILE"
    fi
    if [ -f "$DESKTOP_FILE" ]; then
        say "Меню: $DESKTOP_FILE"
    fi
    if ask "Запустить BlockPulse Launcher сейчас? [y/N] "; then
        exec "$INSTALL_DIR/blockpulse-launcher"
    fi
}
usage() {
    cat <<EOF_USAGE
BlockPulse Launcher $VERSION

./install.sh                    установить
./install.sh --uninstall         удалить лаунчер, игру, настройки и логи
./install.sh --uninstall --keep-game
                                то же, но оставить Minecraft
./install.sh --uninstall-all     то же, плюс удалить пакеты, которые ставил установщик
./install.sh --debug             подробный вывод: что отвечает пакетный менеджер
./install.sh --help
EOF_USAGE
}

KEEP_GAME=0
DEBUG=0
MODE=install
# Every argument is inspected, not just the first: the documented
# `--uninstall --keep-game` used to drop the second flag on the floor, and the
# game directory was removed despite the user asking to keep it.
for arg in "$@"; do
    case "$arg" in
        --help|-h) usage; exit 0 ;;
        --uninstall) MODE=uninstall ;;
        --uninstall-all) MODE=uninstall-all ;;
        --keep-game) KEEP_GAME=1 ;;
        --debug) DEBUG=1 ;;
        "") ;;
        *) usage; exit 2 ;;
    esac
done

if [ "$MODE" != install ]; then
    # dependencies first: the list lives in the state dir that gets wiped below
    [ "$MODE" = uninstall-all ] && uninstall_dependencies
    uninstall_launcher "$KEEP_GAME"
    exit 0
fi

say "BlockPulse Launcher $VERSION"
say "Каталог установки: $INSTALL_DIR"
manager="$(package_manager)"

if [ "$manager" = unsupported ]; then
    say "Поддерживаются Arch-based, Debian-based и Fedora/RHEL-системы (dnf)."
    exit 1
fi

missing_dependencies "$manager"
if [ "${#DEP_MISSING[@]}" -gt 0 ]; then
    say "Не хватает: ${DEP_MISSING[*]}"
    if ask "Установить зависимости автоматически? [Y/n] "; then
        install_dependencies "$manager"
        missing_dependencies "$manager"
        if [ "${#DEP_MISSING[@]}" -gt 0 ]; then
            say "Не все зависимости установлены: ${DEP_MISSING[*]}"
            exit 1
        fi
    else
        say "Установка зависимостей пропущена."
    fi
fi

if [ -e "$INSTALL_DIR" ]; then
    if ! ask "Каталог уже существует. Обновить BlockPulse? [Y/n] "; then
        exit 0
    fi
fi

install_launcher "$manager"
