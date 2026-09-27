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
        /usr/share/java/openjfx/lib \
        /usr/lib/jvm/*openjfx*/lib \
        /usr/lib/jvm/*/lib; do
        [ -f "$c/javafx.controls.jar" ] && { printf '%s\n' "$c"; return 0; }
    done
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
            if ! java21_path >/dev/null 2>&1 && ! dpkg -s openjdk-21-jre >/dev/null 2>&1 && ! dpkg -s openjdk-21-jdk >/dev/null 2>&1; then
                DEP_MISSING+=(openjdk-21-jre)
            fi
            javafx_path >/dev/null 2>&1 || DEP_MISSING+=(openjfx)
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
            javafx_path >/dev/null 2>&1 || DEP_MISSING+=(java-21-openjfx)
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
        root_run pacman -S --needed --noconfirm java21-openjfx
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
    return 1
}
install_fedora_javafx() {
    local dnf pkg
    dnf="$(dnf_cmd)"
    # JavaFX ships per JDK version on Fedora, so the package name follows the
    # runtime. Nothing is built from source and nothing is pulled from a
    # third-party repository: if the matching package is missing, the user
    # chooses the path deliberately.
    for pkg in java-21-openjfx openjfx; do
        if rpm_installed "$pkg" || "$dnf" -q list --available "$pkg" >/dev/null 2>&1; then
            root_run "$dnf" install -y "$pkg"
            record_package "$pkg"
            return 0
        fi
    done
    say ""
    say "В репозиториях нет JavaFX для Java 21, и установщик не берёт его из"
    say "сторонних источников: подключать репозиторий — решение пользователя."
    say "Варианты:"
    say "  * sudo dnf install java-21-openjfx   (обычно есть в fedora)"
    say "  * другой дистрибутив / репозиторий с JavaFX 21"
    say "  * указать JAVA_HOME и JAVAFX_LIB вручную (см. README)"
    return 1
}
install_dependencies() {
    local manager="$1"
    case "$manager" in
        arch)
            if ! pacman -Qq jdk21-openjdk >/dev/null 2>&1 && ! pacman -Qq jre21-openjdk >/dev/null 2>&1; then
                root_run pacman -S --needed --noconfirm jdk21-openjdk
                record_package jdk21-openjdk
            fi
            if ! pacman -Qq xdg-utils >/dev/null 2>&1; then
                root_run pacman -S --needed --noconfirm xdg-utils
                record_package xdg-utils
            fi
            if ! javafx_path >/dev/null 2>&1; then
                # || true: под 'set -e' непустой return оборвал бы установку до
                # итоговой проверки missing_dependencies ниже
                install_arch_javafx || true
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                if ! pacman -Qq xorg-xwayland >/dev/null 2>&1; then
                    root_run pacman -S --needed --noconfirm xorg-xwayland
                    record_package xorg-xwayland
                fi
            fi
            if ! pacman -Qq libsecret >/dev/null 2>&1; then
                root_run pacman -S --needed --noconfirm libsecret
                record_package libsecret
            fi
            ;;
        debian)
            root_run apt-get update
            if ! dpkg -s openjdk-21-jre >/dev/null 2>&1 && ! dpkg -s openjdk-21-jdk >/dev/null 2>&1; then
                root_run apt-get install -y openjdk-21-jre
                record_package openjdk-21-jre
            fi
            if ! dpkg -s openjfx >/dev/null 2>&1; then
                root_run apt-get install -y openjfx
                record_package openjfx
            fi
            if ! dpkg -s xdg-utils >/dev/null 2>&1; then
                root_run apt-get install -y xdg-utils
                record_package xdg-utils
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                if ! dpkg -s xwayland >/dev/null 2>&1; then
                    root_run apt-get install -y xwayland
                    record_package xwayland
                fi
            fi
            if ! dpkg -s libsecret-tools >/dev/null 2>&1; then
                root_run apt-get install -y libsecret-tools
                record_package libsecret-tools
            fi
            ;;
        fedora)
            local dnf
            dnf="$(dnf_cmd)"
            if ! java21_path >/dev/null 2>&1 && ! rpm_installed_any java-21-openjdk java-21-openjdk-headless java-1.21.0-openjdk; then
                root_run "$dnf" install -y java-21-openjdk
                record_package java-21-openjdk
            fi
            if ! javafx_path >/dev/null 2>&1; then
                install_fedora_javafx || true
            fi
            if ! has xdg-open && ! rpm_installed xdg-utils; then
                root_run "$dnf" install -y xdg-utils
                record_package xdg-utils
            fi
            if { [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; } && ! rpm_installed xorg-x11-server-Xwayland; then
                root_run "$dnf" install -y xorg-x11-server-Xwayland
                record_package xorg-x11-server-Xwayland
            fi
            if ! has secret-tool && ! rpm_installed libsecret; then
                root_run "$dnf" install -y libsecret
                record_package libsecret
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

В этот репозиторий официальный билд не входит и не распространяется.
Нужны два файла в app/:
  Launcher.jar                 официальный бэкенд AeroCraft 0.6.2 (не собирается
                               из этого репозитория, скачивается сам)
  blockpulse-launcher-ui.jar   слой для Linux/macOS/BSD (релизный артефакт)

Положить оба в:
  $BASE_DIR/app/

и запустить установку снова.
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
    if java21_path >/dev/null 2>&1 && javafx_path >/dev/null 2>&1; then
        say "Java/JavaFX: готово"
    else
        say "Java/JavaFX: не все зависимости доступны"
    fi
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
./install.sh --help
EOF_USAGE
}

KEEP_GAME=0
MODE=install
case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --uninstall) MODE=uninstall ;;
    --uninstall-all) MODE=uninstall-all ;;
    --keep-game) KEEP_GAME=1 ;;
    "") ;;
    *) usage; exit 2 ;;
esac

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
