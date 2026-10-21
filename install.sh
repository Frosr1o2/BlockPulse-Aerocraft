#!/usr/bin/env bash
set -euo pipefail

PORT_VERSION=1.0.0
LAUNCHER_VERSION=0.6.2
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
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

XDG_DATA_DIR="${XDG_DATA_HOME:-}"
[ -n "$XDG_DATA_DIR" ] && [ "${XDG_DATA_DIR#/}" = "$XDG_DATA_DIR" ] && XDG_DATA_DIR=""
XDG_DATA_DIR="${XDG_DATA_DIR:-$INSTALL_HOME/.local/share}"
CONF_DIR="${XDG_CONFIG_HOME:-$INSTALL_HOME/.config}/blockpulse-launcher"
STATE_DIR="${XDG_STATE_HOME:-$INSTALL_HOME/.local/state}/blockpulse-launcher"
GAME_DIR="$XDG_DATA_DIR/AeroCraft"
PACKAGE_LIST="$STATE_DIR/installed-packages"
SECRET_SERVICE="com.blockpulse.aerocraft.launcher"
LANGUAGE_FILE="$CONF_DIR/language"

TTY=0
[ -t 0 ] && [ -t 1 ] && TTY=1
QUIET=0
DEBUG=0
ASSUME_YES=0
DRY_RUN=0
COLOR=0
if [ "$TTY" = 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    COLOR=1
fi
C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''
if [ "$COLOR" = 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
fi

say() { printf '%s\n' "$*"; }
note() { [ "$QUIET" = 1 ] && return 0; printf '%s\n' "$*"; return 0; }
err() { printf '%s\n' "$*" >&2; }
err_color() { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
clear_line() { [ "$TTY" = 1 ] && printf '\r\033[K'; return 0; }

T_en_lang_prompt='Choose language [1-3]: '
T_ru_lang_prompt='Выберите язык [1-3]: '
T_uk_lang_prompt='Виберіть мову [1-3]: '

T_en_unknown_arg='Unknown option: %s'
T_ru_unknown_arg='Неизвестный параметр: %s'
T_uk_unknown_arg='Невідомий параметр: %s'

T_en_summary='Summary'
T_ru_summary='Итог проверки'
T_uk_summary='Підсумок перевірки'
T_en_sys_line='  System:            %s'
T_ru_sys_line='  Система:           %s'
T_uk_sys_line='  Система:           %s'
T_en_dir_line='  Install directory: %s'
T_ru_dir_line='  Каталог установки: %s'
T_uk_dir_line='  Каталог встановлення: %s'
T_en_java_line='  Java:              %s'
T_ru_java_line='  Java:              %s'
T_uk_java_line='  Java:              %s'
T_en_fx_line='  JavaFX:            %s'
T_ru_fx_line='  JavaFX:            %s'
T_uk_fx_line='  JavaFX:            %s'
T_en_missing_line='  Missing packages:  %s'
T_ru_missing_line='  Не хватает пакетов: %s'
T_uk_missing_line='  Бракує пакетів:    %s'
T_en_not_found='not found'
T_ru_not_found='не найдено'
T_uk_not_found='не знайдено'
T_en_not_found_java='Java 21 not found'
T_ru_not_found_java='Java 21 не найдена'
T_uk_not_found_java='Java 21 не знайдено'
T_en_not_found_fx='JavaFX not found'
T_ru_not_found_fx='JavaFX не найден'
T_uk_not_found_fx='JavaFX не знайдено'
T_en_fx_not_loadable='JavaFX does not load in this environment'
T_ru_fx_not_loadable='JavaFX не загружается этой средой'
T_uk_fx_not_loadable='JavaFX не завантажується цим середовищем'
T_en_continue_q='Continue? [Y/n] '
T_ru_continue_q='Продолжить? [Y/n] '
T_uk_continue_q='Продовжити? [Y/n] '

T_en_unsupported='This distribution is not supported. Arch-based (pacman), Debian-based (apt) and Fedora/RHEL (dnf) are supported.'
T_ru_unsupported='Этот дистрибутив не поддерживается. Поддерживаются Arch (pacman), Debian (apt) и Fedora/RHEL (dnf).'
T_uk_unsupported='Цей дистрибутив не підтримується. Підтримуються Arch (pacman), Debian (apt) і Fedora/RHEL (dnf).'

T_en_artifacts_missing='Missing app/%s'
T_ru_artifacts_missing='Не найден app/%s'
T_uk_artifacts_missing='Не знайдено app/%s'
T_en_artifacts_help='Both files are checked into the repository under app/. The copy looks incomplete.
Get them from:
  https://github.com/Frosr1o2/BlockPulse-Aerocraft

or put both files into:
  %s/app/

and run the installation again.'
T_ru_artifacts_help='Оба файла лежат в репозитории в app/. Похоже, копия неполная.
Возьми их оттуда:
  https://github.com/Frosr1o2/BlockPulse-Aerocraft

или положи оба файла в:
  %s/app/

и запусти установку снова.'
T_uk_artifacts_help='Обидва файли лежать у репозиторії в app/. Схоже, копія неповна.
Візьми їх звідти:
  https://github.com/Frosr1o2/BlockPulse-Aerocraft

або поклади обидва файли в:
  %s/app/

і запусти встановлення знову.'
T_en_artifacts_no_profiles='There is no profile in app/profiles - the installation will continue without them.'
T_ru_artifacts_no_profiles='В app/profiles нет ни одного профиля - установка продолжится без них.'
T_uk_artifacts_no_profiles='У app/profiles немає жодного профілю - встановлення продовжиться без них.'

T_en_deps_ask='Install the missing packages automatically? [Y/n] '
T_ru_deps_ask='Установить недостающие пакеты автоматически? [Y/n] '
T_uk_deps_ask='Встановити відсутні пакети автоматично? [Y/n] '
T_en_deps_skipped='Dependency installation skipped.'
T_ru_deps_skipped='Установка зависимостей пропущена.'
T_uk_deps_skipped='Встановлення залежностей пропущено.'
T_en_deps_incomplete='Some dependencies are still missing: %s'
T_ru_deps_incomplete='Не все зависимости установлены: %s'
T_uk_deps_incomplete='Не всі залежності встановлено: %s'
T_en_dir_exists_q='The directory already exists. Update BlockPulse? [Y/n] '
T_ru_dir_exists_q='Каталог уже существует. Обновить BlockPulse? [Y/n] '
T_uk_dir_exists_q='Каталог уже існує. Оновити BlockPulse? [Y/n] '

T_en_step_verify='Checking files'
T_ru_step_verify='Проверка файлов'
T_uk_step_verify='Перевірка файлів'
T_en_step_deps='Installing system packages'
T_ru_step_deps='Установка системных пакетов'
T_uk_step_deps='Встановлення системних пакетів'
T_en_step_copy='Copying launcher files'
T_ru_step_copy='Копирование файлов лаунчера'
T_uk_step_copy='Копіювання файлів лаунчера'
T_en_step_shortcuts='Creating shortcuts'
T_ru_step_shortcuts='Создание ярлыков'
T_uk_step_shortcuts='Створення ярликів'
T_en_step_status='Checking the runtime'
T_ru_step_status='Проверка среды запуска'
T_uk_step_status='Перевірка середовища запуску'
T_en_step_failed='Step failed: %s'
T_ru_step_failed='Шаг не выполнен: %s'
T_uk_step_failed='Крок не виконано: %s'
T_en_step_log='Full log: %s'
T_ru_step_log='Полный лог: %s'
T_uk_step_log='Повний лог: %s'

T_en_installed='Installed: %s'
T_ru_installed='Установлено: %s'
T_uk_installed='Встановлено: %s'
T_en_version_port='BlockPulse Aerocraft port %s'
T_ru_version_port='Порт BlockPulse Aerocraft %s'
T_uk_version_port='Порт BlockPulse Aerocraft %s'
T_en_version_launcher='Bundled launcher %s'
T_ru_version_launcher='Встроенный лаунчер %s'
T_uk_version_launcher='Вбудований лаунчер %s'
T_en_version_line='Port version: %s; bundled launcher: %s'
T_ru_version_line='Версия порта: %s; встроенный лаунчер: %s'
T_uk_version_line='Версія порту: %s; вбудований лаунчер: %s'
T_en_javafx_ready='Java/JavaFX: ready - %s'
T_ru_javafx_ready='Java/JavaFX: готово - %s'
T_uk_javafx_ready='Java/JavaFX: готово - %s'
T_en_javafx_old='Java/JavaFX: %s (21 or newer is required)'
T_ru_javafx_old='Java/JavaFX: %s (нужен 21 или новее)'
T_uk_javafx_old='Java/JavaFX: %s (потрібен 21 або новіший)'
T_en_javafx_none='Java/JavaFX: not ready - %s'
T_ru_javafx_none='Java/JavaFX: не готово - %s'
T_uk_javafx_none='Java/JavaFX: не готово - %s'
T_en_javafx_old_hint='The distribution JavaFX is older than the build needs.
The installer does not add third-party PPAs: the choice is yours.
Options:
  * a distribution that ships JavaFX 21 (Debian 13 and newer)
  * SDKMAN or coursier: a ready JavaFX 21 next to Java 21
  * ./blockpulse-launcher --diagnose shows whether the module loads'
T_ru_javafx_old_hint='Пакет JavaFX в этом дистрибутиве старее, чем требует сборка.
Установщик не подключает сторонние PPA: решение за вами.
Варианты:
  * дистрибутив с JavaFX 21 (Debian 13 и новее)
  * SDKMAN или coursier: готовый JavaFX 21 рядом с Java 21
  * ./blockpulse-launcher --diagnose покажет, грузится ли модуль'
T_uk_javafx_old_hint='Пакет JavaFX у цьому дистрибутиві старіший, ніж потребує збірка.
Встановлювач не підключає сторонні PPA: рішення за тобою.
Варіанти:
  * дистрибутив з JavaFX 21 (Debian 13 і новіший)
  * SDKMAN або coursier: готовий JavaFX 21 поруч із Java 21
  * ./blockpulse-launcher --diagnose покаже, чи завантажується модуль'

T_en_add_command_q='Add the blockpulse-launcher command to ~/.local/bin? [Y/n] '
T_ru_add_command_q='Добавить команду blockpulse-launcher в ~/.local/bin? [Y/n] '
T_uk_add_command_q='Додати команду blockpulse-launcher у ~/.local/bin? [Y/n] '
T_en_add_desktop_q='Add BlockPulse to the application menu and XDG launchers? [Y/n] '
T_ru_add_desktop_q='Добавить BlockPulse в меню приложений и XDG-лаунчеры? [Y/n] '
T_uk_add_desktop_q='Додати BlockPulse до меню програм і XDG-лаунчерів? [Y/n] '
T_en_command_path='Command: %s'
T_ru_command_path='Команда: %s'
T_uk_command_path='Команда: %s'
T_en_menu_path='Menu entry: %s'
T_ru_menu_path='Меню: %s'
T_uk_menu_path='Меню: %s'
T_en_launch_q='Run BlockPulse Launcher now? [y/N] '
T_ru_launch_q='Запустить BlockPulse Launcher сейчас? [y/N] '
T_uk_launch_q='Запустити BlockPulse Launcher зараз? [y/N] '

T_en_menu_title='What next?'
T_ru_menu_title='Что дальше?'
T_uk_menu_title='Що далі?'
T_en_menu_launch='  1) Run the launcher'
T_ru_menu_launch='  1) Запустить лаунчер'
T_uk_menu_launch='  1) Запустити лаунчер'
T_en_menu_diag='  2) Run diagnostics'
T_ru_menu_diag='  2) Диагностика'
T_uk_menu_diag='  2) Діагностика'
T_en_menu_exit='  3) Exit'
T_ru_menu_exit='  3) Выход'
T_uk_menu_exit='  3) Вихід'
T_en_menu_choice='Choice [1-3]: '
T_ru_menu_choice='Выбор [1-3]: '
T_uk_menu_choice='Вибір [1-3]: '

T_en_uninstall_title='Removing BlockPulse Launcher'
T_ru_uninstall_title='Удаление BlockPulse Launcher'
T_uk_uninstall_title='Видалення BlockPulse Launcher'
T_en_will_remove='The following will be removed:'
T_ru_will_remove='Будет удалено:'
T_uk_will_remove='Буде видалено:'
T_en_rm_program='  program:          %s'
T_ru_rm_program='  программа:        %s'
T_uk_rm_program='  програма:         %s'
T_en_rm_game='  game and assets:  %s (%s)'
T_ru_rm_game='  игра и ресурсы:   %s (%s)'
T_uk_rm_game='  гра та ресурси:   %s (%s)'
T_en_rm_settings='  settings:         %s'
T_ru_rm_settings='  настройки:        %s'
T_uk_rm_settings='  налаштування:     %s'
T_en_rm_logs='  logs:             %s'
T_ru_rm_logs='  логи:             %s'
T_uk_rm_logs='  логи:             %s'
T_en_rm_keyring='  saved password in the system keyring (secret-tool, service %s)'
T_ru_rm_keyring='  пароль в связке ключей (secret-tool, служба %s)'
T_uk_rm_keyring='  пароль у зв’язці ключів (secret-tool, служба %s)'
T_en_rm_kind_program='program'
T_ru_rm_kind_program='программу'
T_uk_rm_kind_program='програму'
T_en_rm_kind_game='game'
T_ru_rm_kind_game='игру'
T_uk_rm_kind_game='гру'
T_en_rm_kind_settings='settings'
T_ru_rm_kind_settings='настройки'
T_uk_rm_kind_settings='налаштування'
T_en_rm_kind_logs='logs'
T_ru_rm_kind_logs='логи'
T_uk_rm_kind_logs='логи'
T_en_confirm_remove='Remove the launcher, settings and logs? [y/N] '
T_ru_confirm_remove='Удалить лаунчер, настройки и логи? [y/N] '
T_uk_confirm_remove='Видалити лаунчер, налаштування та логи? [y/N] '
T_en_cancelled='Cancelled.'
T_ru_cancelled='Отменено.'
T_uk_cancelled='Скасовано.'
T_en_nothing_to_remove='Nothing found, there is nothing to remove.'
T_ru_nothing_to_remove='Ничего не найдено, удалять нечего.'
T_uk_nothing_to_remove='Нічого не знайдено, видаляти нічого.'
T_en_game_warn='WARNING: the game, Minecraft and every downloaded asset will be deleted permanently (%s, %s).'
T_ru_game_warn='ВНИМАНИЕ: вместе с лаунчером будет безвозвратно удалён Minecraft и все скачанные ресурсы (%s, %s).'
T_uk_game_warn='УВАГА: разом із лаунчером буде безповоротно видалено Minecraft і всі завантажені ресурси (%s, %s).'
T_en_confirm_game='Delete the game as well? [y/N] '
T_ru_confirm_game='Удалить игру тоже? [y/N] '
T_uk_confirm_game='Видалити гру також? [y/N] '
T_en_game_kept='The game directory was kept.'
T_ru_game_kept='Игра оставлена.'
T_uk_game_kept='Гру залишено.'
T_en_removing='  removing %s: %s (%s)'
T_ru_removing='  удаляю %s: %s (%s)'
T_uk_removing='  видаляю %s: %s (%s)'
T_en_skip_unsafe='Skipping %s: unsafe path.'
T_ru_skip_unsafe='Пропуск %s: небезопасный путь.'
T_uk_skip_unsafe='Пропуск %s: небезпечний шлях.'
T_en_removed_done='BlockPulse Launcher removed.'
T_ru_removed_done='BlockPulse Launcher удалён.'
T_uk_removed_done='BlockPulse Launcher видалено.'
T_en_rm_password='  removing the saved password from the keyring'
T_ru_rm_password='  удаляю сохранённый пароль из связки ключей'
T_uk_rm_password='  видаляю збережений пароль зі зв’язки ключів'

T_en_deps_none_list='No package list found: %s'
T_ru_deps_none_list='Список установленных пакетов не найден: %s'
T_uk_deps_none_list='Список встановлених пакетів не знайдено: %s'
T_en_deps_none_installed='This program did not install any packages.'
T_ru_deps_none_installed='Зависимости не устанавливались этой программой.'
T_uk_deps_none_installed='Залежності не встановлювалися цією програмою.'
T_en_deps_present_none='None of those packages are installed.'
T_ru_deps_present_none='Установленных пакетов не найдено.'
T_uk_deps_present_none='Встановлених пакетів не знайдено.'
T_en_deps_will_remove='Packages installed by the installer will be removed: %s'
T_ru_deps_will_remove='Будут удалены пакеты, которые поставил установщик: %s'
T_uk_deps_will_remove='Буде видалено пакети, які встановив інсталятор: %s'
T_en_deps_rm_hint='(-Rns / autoremove also removes dependencies that only they need)'
T_ru_deps_rm_hint='(-Rns / autoremove: уйдут и зависимости, которые нужны только им)'
T_uk_deps_rm_hint='(-Rns / autoremove: підуть і залежності, потрібні лише їм)'
T_en_confirm_deps='Remove them? [y/N] '
T_ru_confirm_deps='Удалить? [y/N] '
T_uk_confirm_deps='Видалити? [y/N] '
T_en_deps_removed='Packages removed.'
T_ru_deps_removed='Зависимости удалены.'
T_uk_deps_removed='Залежності видалено.'

T_en_no_sudo='sudo is required to install packages, but it is not available.'
T_ru_no_sudo='Для установки пакетов нужен sudo, но он недоступен.'
T_uk_no_sudo='Для встановлення пакетів потрібен sudo, але він недоступний.'
T_en_dry_run_done='Dry run: nothing was changed.'
T_ru_dry_run_done='Пробный запуск: ничего не изменено.'
T_uk_dry_run_done='Пробний запуск: нічого не змінено.'
T_en_log_path='Log: %s'
T_ru_log_path='Лог: %s'
T_uk_log_path='Лог: %s'

T_en_usage_title='BlockPulse Aerocraft port %s (launcher %s)'
T_ru_usage_title='Порт BlockPulse Aerocraft %s (лаунчер %s)'
T_uk_usage_title='Порт BlockPulse Aerocraft %s (лаунчер %s)'
T_en_usage_install='  ./install.sh                    install'
T_ru_usage_install='  ./install.sh                    установить'
T_uk_usage_install='  ./install.sh                    встановити'
T_en_usage_uninstall='  ./install.sh --uninstall         remove the launcher, game, settings and logs'
T_ru_usage_uninstall='  ./install.sh --uninstall         удалить лаунчер, игру, настройки и логи'
T_uk_usage_uninstall='  ./install.sh --uninstall         видалити лаунчер, гру, налаштування та логи'
T_en_usage_keep='  ./install.sh --uninstall --keep-game     keep Minecraft'
T_ru_usage_keep='  ./install.sh --uninstall --keep-game     оставить Minecraft'
T_uk_usage_keep='  ./install.sh --uninstall --keep-game     залишити Minecraft'
T_en_usage_all='  ./install.sh --uninstall-all     also remove the packages the installer added'
T_ru_usage_all='  ./install.sh --uninstall-all     ещё и удалить пакеты, которые ставил установщик'
T_uk_usage_all='  ./install.sh --uninstall-all     ще й видалити пакети, які встановив інсталятор'
T_en_usage_quiet='  --quiet, -q                     no package-manager noise, one progress line'
T_ru_usage_quiet='  --quiet, -q                     без шума пакетного менеджера, одна строка прогресса'
T_uk_usage_quiet='  --quiet, -q                     без шуму пакетного менеджера, один рядок прогресу'
T_en_usage_lang='  --lang uk|ru|en                 interface language'
T_ru_usage_lang='  --lang uk|ru|en                 язык интерфейса'
T_uk_usage_lang='  --lang uk|ru|en                 мова інтерфейсу'
T_en_usage_yes='  --yes, -y                       answer "yes" to every question'
T_ru_usage_yes='  --yes, -y                       отвечать "да" на все вопросы'
T_uk_usage_yes='  --yes, -y                       відповідати "так" на всі питання'
T_en_usage_debug='  --debug                         verbose output, including package managers'
T_ru_usage_debug='  --debug                         подробный вывод, включая пакетные менеджеры'
T_uk_usage_debug='  --debug                         докладний вивід, включно з пакетними менеджерами'
T_en_usage_dry='  --dry-run                       detect everything, change nothing'
T_ru_usage_dry='  --dry-run                       всё проверить, ничего не менять'
T_uk_usage_dry='  --dry-run                       все перевірити, нічого не змінювати'
T_en_usage_help='  --help, -h                      this help'
T_ru_usage_help='  --help, -h                      эта справка'
T_uk_usage_help='  --help, -h                      ця довідка'
T_en_usage_version='  --version, -V                   print the version and exit'
T_ru_usage_version='  --version, -V                   показать версию и выйти'
T_uk_usage_version='  --version, -V                   показати версію та вийти'
T_en_usage_install_hdr='Install'
T_ru_usage_install_hdr='Установка'
T_uk_usage_install_hdr='Встановлення'
T_en_usage_remove_hdr='Removal'
T_ru_usage_remove_hdr='Удаление'
T_uk_usage_remove_hdr='Видалення'
T_en_usage_output_hdr='Output and language'
T_ru_usage_output_hdr='Вывод и язык'
T_uk_usage_output_hdr='Вивід і мова'
T_en_usage_other_hdr='Other'
T_ru_usage_other_hdr='Прочее'
T_uk_usage_other_hdr='Інше'
T_en_usage_examples='Examples'
T_ru_usage_examples='Примеры'
T_uk_usage_examples='Приклади'
T_en_help_hint='All options: ./install.sh --help'
T_ru_help_hint='Все параметры: ./install.sh --help'
T_uk_help_hint='Усі параметри: ./install.sh --help'

LANG_CODE=''
t() {
    local key="$1"; shift
    local var="T_${LANG_CODE}_${key}"
    local text="${!var-}"
    if [ -z "$text" ]; then
        var="T_en_${key}"
        text="${!var-}"
    fi
    if [ -z "$text" ]; then
        printf '%s\n' "$key"
        return 0
    fi
    printf -- "$text" "$@"
}

detect_lang() {
    case "${BLOCKPULSE_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}" in
        uk*|UK*|ua*|UA*) printf 'uk' ;;
        ru*|RU*)         printf 'ru' ;;
        en*|EN*)         printf 'en' ;;
        *)               printf '' ;;
    esac
}

choose_language() {
    if [ -n "${LANG_ARG:-}" ]; then
        LANG_CODE="$LANG_ARG"
        return 0
    fi
    local detected
    detected="$(detect_lang)"
    if [ "$TTY" != 1 ] || [ "$ASSUME_YES" = 1 ]; then
        LANG_CODE="${detected:-en}"
        return 0
    fi
    say "1) Українська    2) Русский    3) English"
    LANG_CODE="${detected:-en}"
    local choice
    printf '%s' "$(t lang_prompt)"
    read -r choice || { printf '\n'; return 0; }
    case "${choice:-}" in
        1|uk|ua) LANG_CODE=uk ;;
        2|ru)    LANG_CODE=ru ;;
        3|en)    LANG_CODE=en ;;
        '')      : ;;
        *)       : ;;
    esac
}

has() { command -v "$1" >/dev/null 2>&1; }
ask() {
    local prompt="$1" default="${2:-y}" answer
    if [ "$ASSUME_YES" = 1 ]; then
        return 0
    fi
    if [ "$TTY" != 1 ]; then
        [ "$default" = y ] && return 0
        return 1
    fi
    clear_line
    printf '%s' "$prompt"
    read -r answer || { printf '\n'; return 1; }
    answer="${answer:-$default}"
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]|1|д|Д|да|Да|т|Т|так|Так) return 0 ;;
        *) return 1 ;;
    esac
}
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
        chown -R "$INSTALL_USER:$(id -gn "$INSTALL_USER")" "$@" 2>/dev/null || true
    fi
}
put_file() {
    local mode="$1" src="$2" dst="$3"
    mkdir -p "$(dirname "$dst")"
    if ! install -m "$mode" "$src" "$dst" 2>/dev/null; then
        cp -f "$src" "$dst"
        chmod "$mode" "$dst"
    fi
}
os_name() {
    if [ -r /etc/os-release ]; then
        ( . /etc/os-release; printf '%s' "${PRETTY_NAME:-$(uname -s)}" )
    else
        printf '%s' "$(uname -s)"
    fi
}
ensure_sudo() {
    [ "$(id -u)" -eq 0 ] && return 0
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    if [ "$TTY" != 1 ]; then
        return 0
    fi
    clear_line
    say "sudo:"
    sudo -v || return 1
}

_JAVA21_CACHE=''; _JAVA21_DONE=0
JAVAFX_CACHE=''; _JAVAFX_DONE=0
JAVAFX_STATUS_TEXT=''; JAVAFX_STATUS_KIND=''; _JAVAFX_STATUS_DONE=0
reset_probe_cache() {
    _JAVA21_DONE=0; _JAVAFX_DONE=0; _JAVAFX_STATUS_DONE=0
    _JAVA21_CACHE=''; JAVAFX_CACHE=''
    JAVAFX_STATUS_TEXT=''; JAVAFX_STATUS_KIND=''
}
java21_path() {
    if [ "$_JAVA21_DONE" = 1 ]; then
        [ -n "$_JAVA21_CACHE" ] || return 1
        printf '%s\n' "$_JAVA21_CACHE"
        return 0
    fi
    local c major out
    local -a candidates=()
    [ -n "${BLOCKPULSE_JAVA:-}" ] && candidates+=("$BLOCKPULSE_JAVA")
    [ -n "${JAVA_HOME:-}" ] && candidates+=("$JAVA_HOME/bin/java")
    while IFS= read -r c; do candidates+=("$c"); done < <(printf '%s\n' /usr/lib/jvm/*/bin/java "$HOME"/.sdkman/candidates/java/*/bin/java "$HOME"/.jdks/*/bin/java 2>/dev/null)
    c="$(command -v java 2>/dev/null || true)"
    [ -n "$c" ] && candidates+=("$c")
    for c in "${candidates[@]}"; do
        [ -x "$c" ] || continue
        out="$("$c" -version 2>&1 || true)"
        major="$(printf '%s\n' "$out" | sed -n '1s/.*version "\([0-9]*\).*/\1/p')"
        if [ -n "$major" ] && [ "$major" -ge 21 ] 2>/dev/null; then
            _JAVA21_CACHE="$c"; _JAVA21_DONE=1
            printf '%s\n' "$c"
            return 0
        fi
    done
    _JAVA21_DONE=1
    return 1
}
javafx_path() {
    if [ "$_JAVAFX_DONE" = 1 ]; then
        [ -n "$JAVAFX_CACHE" ] || return 1
        printf '%s\n' "$JAVAFX_CACHE"
        return 0
    fi
    local c java_path found
    java_path="$(java21_path 2>/dev/null || true)"
    if [ -n "${JAVAFX_LIB:-}" ] && [ -f "$JAVAFX_LIB/javafx.controls.jar" ]; then
        JAVAFX_CACHE="$JAVAFX_LIB"; _JAVAFX_DONE=1
        printf '%s\n' "$JAVAFX_CACHE"
        return 0
    fi
    if [ -n "$java_path" ] && "$java_path" --list-modules 2>/dev/null | grep -q '^javafx.controls@'; then
        JAVAFX_CACHE=bundled; _JAVAFX_DONE=1
        printf '%s\n' "$JAVAFX_CACHE"
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
        [ -f "$c/javafx.controls.jar" ] && { JAVAFX_CACHE="$c"; _JAVAFX_DONE=1; printf '%s\n' "$c"; return 0; }
    done
    if rpm_installed_any openjfx java-21-openjfx java-22-openjfx java-23-openjfx; then
        found="$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | grep -ixE 'openjfx|java-[0-9]+-openjfx' \
            | while IFS= read -r pkg; do rpm -ql "$pkg" 2>/dev/null; done \
            | awk -F/ '$NF == "javafx.controls.jar" {print $0}' | head -1)"
        if [ -n "$found" ] && [ -f "$found" ]; then
            JAVAFX_CACHE="$(dirname "$found")"; _JAVAFX_DONE=1
            printf '%s\n' "$JAVAFX_CACHE"
            return 0
        fi
    fi
    _JAVAFX_DONE=1
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

STEP_CUR=0
STEP_TOTAL=1
SPIN='|/-\'
phase() { STEP_TOTAL="$1"; STEP_CUR=0; }
draw_progress() {
    local label="$1" cur="$2" frame="${3:-0}" pct filled width=22 bar='' pad=''
    pct=$(( cur * 100 / STEP_TOTAL ))
    [ "$pct" -gt 100 ] && pct=100
    filled=$(( pct * width / 100 ))
    printf -v bar '%*s' "$filled" ''
    bar="${bar// /#}"
    printf -v pad '%*s' "$(( width - filled ))" ''
    pad="${pad// /-}"
    printf '\r\033[K  %s[%s%s]%s %3d%%  %s%s' "$C_DIM" "$bar" "$pad" "$C_RESET" "$pct" "$label" "${SPIN:frame%4:1}"
}
run_step() {
    local label="$1"; shift
    local next=$(( STEP_CUR + 1 )) rc=0
    [ "$DEBUG" = 1 ] && note "  ${C_DIM}*${C_RESET} $label"
    : >"$RUN_LOG"
    if [ "$DEBUG" = 1 ]; then
        "$@" 2>&1 | tee -a "$INSTALL_LOG"
        rc=${PIPESTATUS[0]}
    else
        if [ "$QUIET" = 1 ] && [ "$TTY" != 1 ]; then
            printf '  [%d/%d] %3d%%  %s\n' "$next" "$STEP_TOTAL" "$(( next * 100 / STEP_TOTAL ))" "$label"
        elif [ "$QUIET" != 1 ]; then
            printf '  %s*%s %s\n' "$C_DIM" "$C_RESET" "$label"
        fi
        "$@" >>"$RUN_LOG" 2>&1 &
        local pid=$! frame=0
        if [ "$QUIET" = 1 ] && [ "$TTY" = 1 ]; then
            while kill -0 "$pid" 2>/dev/null; do
                draw_progress "$label" "$next" "$frame"
                frame=$(( (frame + 1) % 4 ))
                sleep 0.2
            done
            clear_line
        fi
        if wait "$pid"; then rc=0; else rc=$?; fi
        if [ -s "$RUN_LOG" ]; then
            { printf '### %s\n' "$label"; cat "$RUN_LOG"; } >>"$INSTALL_LOG"
        fi
    fi
    STEP_CUR=$next
    [ "$STEP_CUR" -gt "$STEP_TOTAL" ] && STEP_CUR=$STEP_TOTAL
    if [ "$rc" -eq 0 ]; then
        if [ "$QUIET" = 1 ] && [ "$TTY" = 1 ]; then
            draw_progress "$label" "$STEP_CUR" 0
            printf ' %sok%s\n' "$C_GREEN" "$C_RESET"
        fi
    else
        clear_line
        err_color "  $(t step_failed "$label")"
        if [ -s "$RUN_LOG" ]; then
            tail -n 15 "$RUN_LOG" | sed 's/^/    /' >&2
        fi
        err "  $(t step_log "$INSTALL_LOG")"
    fi
    return "$rc"
}
rotate_log() {
    if [ -f "$INSTALL_LOG" ] && [ "$(wc -c <"$INSTALL_LOG" 2>/dev/null || printf 0)" -gt 2097152 ]; then
        mv -f "$INSTALL_LOG" "$INSTALL_LOG.old" 2>/dev/null || true
    fi
}

javafx_status() {
    if [ "$_JAVAFX_STATUS_DONE" = 1 ]; then
        [ "$JAVAFX_STATUS_KIND" = ok ]
        return $?
    fi
    _JAVAFX_STATUS_DONE=1
    local java_path fx_dir line version major fx_path=''
    java_path="$(java21_path 2>/dev/null || true)"
    if [ -z "${java_path:-}" ]; then
        JAVAFX_STATUS_TEXT="$(t not_found_java)"; JAVAFX_STATUS_KIND=missing_java
        return 1
    fi
    fx_dir="$(javafx_path 2>/dev/null || true)"
    if [ -z "${fx_dir:-}" ]; then
        JAVAFX_STATUS_TEXT="$(t not_found_fx)"; JAVAFX_STATUS_KIND=missing_fx
        return 1
    fi
    if [ "$fx_dir" = bundled ]; then
        line="$("$java_path" --list-modules 2>/dev/null | grep -E '^javafx\.controls@' | head -1)"
    else
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
    if [ -z "${line:-}" ]; then
        JAVAFX_STATUS_TEXT="$(t fx_not_loadable)"; JAVAFX_STATUS_KIND=not_loadable
        return 1
    fi
    version="$(printf '%s\n' "$line" | sed -n 's/.*@\([0-9][0-9.]*\).*/\1/p')"
    if [ -z "$version" ]; then
        JAVAFX_STATUS_TEXT="$(t fx_not_loadable)"; JAVAFX_STATUS_KIND=not_loadable
        return 1
    fi
    major="$(printf '%s\n' "$version" | cut -d. -f1)"
    case "$major" in
        ''|*[!0-9]*)
            JAVAFX_STATUS_TEXT="JavaFX $version"; JAVAFX_STATUS_KIND=old
            return 1
            ;;
        *)
            if [ "$major" -ge 21 ] 2>/dev/null; then
                JAVAFX_STATUS_TEXT="JavaFX $version"; JAVAFX_STATUS_KIND=ok
                return 0
            fi
            JAVAFX_STATUS_TEXT="JavaFX $version"; JAVAFX_STATUS_KIND=old
            return 1
            ;;
    esac
}
try_root_run() {
    if root_run "$@"; then
        return 0
    fi
    err "Failed to run: $*"
    return 1
}
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
debian_package_available() {
    dpkg -s "$1" >/dev/null 2>&1 && return 0
    has apt-cache || return 1
    apt-cache policy "$1" 2>/dev/null | grep -qE "^[[:space:]]*Candidate: [^(]" && return 0
    apt-cache show "$1" >/dev/null 2>&1
}
debian_explain_missing() {
    [ "$DEBUG" = 1 ] || return 0
    note ""
    note "apt says about the first candidate ($1):"
    if has apt-cache; then
        apt-cache policy "$1" 2>&1 | sed -n '1,6p' | while IFS= read -r line; do note "  $line"; done
        note "Index files: $(ls /var/lib/apt/lists/*Packages* 2>/dev/null | wc -l)"
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
fedora_javafx_package() {
    local dnf pkg
    dnf="$(dnf_cmd)"
    for pkg in java-21-openjfx openjfx; do
        rpm_installed "$pkg" && { printf '%s\n' "$pkg"; return 0; }
        "$dnf" -q list --available "$pkg" >/dev/null 2>&1 && { printf '%s\n' "$pkg"; return 0; }
    done
    return 1
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
    err ""
    err "No JavaFX package in this repository, and building from the AUR is disabled:"
    err "the installer does not run a PKGBUILD fetched from the network."
    err "Options:"
    err "  * Arch:           sudo pacman -S java21-openjfx   (usually in extra)"
    err "  * another distro / repository with JavaFX 21"
    err "  * set JAVA_HOME and JAVAFX_LIB manually (see README)"
    return 1
}
install_fedora_javafx() {
    local dnf pkg
    dnf="$(dnf_cmd)"
    if pkg="$(fedora_javafx_package)"; then
        if ! try_root_run "$dnf" install -y "$pkg"; then
            return 1
        fi
        record_package "$pkg"
        return 0
    fi
    err ""
    err "No JavaFX for Java 21 in the repositories, and the installer does not take it"
    err "from third-party sources: adding a repository is the user's decision."
    err "Options:"
    err "  * sudo dnf install openjfx             (Fedora 41+, standalone JavaFX)"
    err "  * sudo dnf install java-21-openjfx     (Fedora 40 and older, per-JDK)"
    err "  * another distro / repository with JavaFX 21"
    err "  * set JAVA_HOME and JAVAFX_LIB manually (see README)"
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
    err ""
    err "No JavaFX package in the repositories, and the installer does not add"
    err "third-party PPAs: that decision stays with the user."
    err "Options:"
    err "  * sudo apt-get install openjfx"
    err "    (!) On Ubuntu 24.04 and Mint 22 this package is JavaFX 11, the build needs 21."
    err "      JavaFX 21 is in Debian 13 and newer, or install it through SDKMAN/coursier."
    err "  * set JAVA_HOME and JAVAFX_LIB manually (see README)"
    return 1
}
install_dependencies() {
    local manager="$1" java_pkg
    case "$manager" in
        arch)
            if ! pacman -Qq jdk21-openjdk >/dev/null 2>&1 && ! pacman -Qq jre21-openjdk >/dev/null 2>&1; then
                { try_root_run pacman -S --needed --noconfirm jdk21-openjdk && record_package jdk21-openjdk; } || true
            fi
            if ! pacman -Qq xdg-utils >/dev/null 2>&1; then
                { try_root_run pacman -S --needed --noconfirm xdg-utils && record_package xdg-utils; } || true
            fi
            if ! javafx_path >/dev/null 2>&1; then
                install_arch_javafx || true
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                if ! pacman -Qq xorg-xwayland >/dev/null 2>&1; then
                    { try_root_run pacman -S --needed --noconfirm xorg-xwayland && record_package xorg-xwayland; } || true
                fi
            fi
            if ! pacman -Qq libsecret >/dev/null 2>&1; then
                { try_root_run pacman -S --needed --noconfirm libsecret && record_package libsecret; } || true
            fi
            ;;
        debian)
            if ! apt_update; then
                err ""
                err "apt-get update failed even without the CD-ROM source."
                err "Trying to install with the current package lists; if a package"
                err "is not found, the installer will print what apt answers."
            fi
            if ! java21_path >/dev/null 2>&1; then
                if java_pkg="$(debian_java_package)"; then
                    { try_root_run apt-get install -y "$java_pkg" && record_package "$java_pkg"; } || true
                else
                    err ""
                    err "No Java 21 in the repositories, and the installer does not add"
                    err "third-party PPAs. Ubuntu 22.04 and Mint 21 do not have it at all:"
                    err "  * move to Ubuntu 24.04 / Mint 22 or newer"
                    err "  * or set JAVA_HOME manually (see README)"
                    debian_explain_missing "openjdk-21-jre"
                fi
            fi
            if ! javafx_path >/dev/null 2>&1; then
                install_debian_javafx || true
            fi
            if ! dpkg -s xdg-utils >/dev/null 2>&1; then
                { try_root_run apt-get install -y xdg-utils && record_package xdg-utils; } || true
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
                if ! dpkg -s xwayland >/dev/null 2>&1; then
                    { try_root_run apt-get install -y xwayland && record_package xwayland; } || true
                fi
            fi
            if ! dpkg -s libsecret-tools >/dev/null 2>&1; then
                { try_root_run apt-get install -y libsecret-tools && record_package libsecret-tools; } || true
            fi
            ;;
        fedora)
            local dnf
            dnf="$(dnf_cmd)"
            if ! java21_path >/dev/null 2>&1 && ! rpm_installed_any java-21-openjdk java-21-openjdk-headless java-1.21.0-openjdk; then
                { try_root_run "$dnf" install -y java-21-openjdk && record_package java-21-openjdk; } || true
            fi
            if ! javafx_path >/dev/null 2>&1; then
                install_fedora_javafx || true
            fi
            if ! has xdg-open && ! rpm_installed xdg-utils; then
                { try_root_run "$dnf" install -y xdg-utils && record_package xdg-utils; } || true
            fi
            if { [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; } && ! rpm_installed xorg-x11-server-Xwayland; then
                { try_root_run "$dnf" install -y xorg-x11-server-Xwayland && record_package xorg-x11-server-Xwayland; } || true
            fi
            if ! has secret-tool && ! rpm_installed libsecret; then
                { try_root_run "$dnf" install -y libsecret && record_package libsecret; } || true
            fi
            ;;
    esac
    return 0
}
record_package() {
    mkdir -p "$STATE_DIR"
    if [ -f "$PACKAGE_LIST" ] && grep -qxF "$1" "$PACKAGE_LIST"; then
        return 0
    fi
    printf '%s\n' "$1" >>"$PACKAGE_LIST"
    chown_user "$STATE_DIR"
}
write_desktop() {
    mkdir -p "$DESKTOP_DIR" "$ICON_DIR"
    put_file 644 "$BASE_DIR/blockpulse-launcher.png" "$ICON_FILE"
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
    local path="$1" kb
    kb="$(du -sk "$path" 2>/dev/null | awk 'NR==1 {print $1}')" || kb=""
    if [ -z "$kb" ]; then
        printf '?'
        return 0
    fi
    awk -v k="$kb" 'BEGIN {
        b = k * 1024;
        split("B KiB MiB GiB TiB", u, " ");
        i = 1;
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i];
    }'
}
remove_path() {
    local path="$1" kind="$2"
    [ -e "$path" ] || return 0
    [ -n "$path" ] && [ "$path" != "/" ] && [ "$path" != "$INSTALL_HOME" ] || {
        say "  $(t skip_unsafe "$path")"
        return 0
    }
    say "$(t removing "$kind" "$path" "$(human_size "$path")")"
    rm -rf "$path"
}
clear_keyring() {
    has secret-tool || return 0
    if secret-tool lookup service "$SECRET_SERVICE" account x >/dev/null 2>&1; then
        say "$(t rm_password)"
        secret-tool clear service "$SECRET_SERVICE" >/dev/null 2>&1 || true
    fi
}
uninstall_launcher() {
    local keep_game="$1" found=0
    say ""
    say "${C_BOLD}$(t uninstall_title)${C_RESET}"
    [ -d "$INSTALL_DIR" ] && found=1
    [ -e "$GAME_DIR" ] && found=1
    [ -e "$CONF_DIR" ] && found=1
    if [ "$found" = 0 ]; then
        say "$(t nothing_to_remove)"
        return 0
    fi
    say "$(t will_remove)"
    say "$(t rm_program "$INSTALL_DIR")"
    [ "$keep_game" = 0 ] && say "$(t rm_game "$GAME_DIR" "$(human_size "$GAME_DIR")")"
    say "$(t rm_settings "$CONF_DIR")"
    say "$(t rm_logs "$STATE_DIR")"
    say "$(t rm_keyring "$SECRET_SERVICE")"
    ask "$(t confirm_remove)" n || { say "$(t cancelled)"; return 0; }

    if [ "$keep_game" = 0 ] && [ -e "$GAME_DIR" ]; then
        say ""
        err_color "$(t game_warn "$GAME_DIR" "$(human_size "$GAME_DIR")")"
        ask "$(t confirm_game)" n || { say "$(t game_kept)"; keep_game=1; }
    fi

    remove_path "$INSTALL_DIR" "$(t rm_kind_program)"
    rm -f "$LINK_FILE"
    remove_desktop
    rmdir "$BIN_DIR" 2>/dev/null || true

    if [ "$keep_game" = 0 ]; then
        remove_path "$GAME_DIR" "$(t rm_kind_game)"
    else
        say "  $(t game_kept) $GAME_DIR"
    fi
    clear_keyring
    remove_path "$CONF_DIR" "$(t rm_kind_settings)"
    remove_path "$STATE_DIR" "$(t rm_kind_logs)"
    say "${C_GREEN}$(t removed_done)${C_RESET}"
}
uninstall_dependencies() {
    [ -f "$PACKAGE_LIST" ] || { say "$(t deps_none_list "$PACKAGE_LIST")"; return 0; }
    local manager packages present pkg
    manager="$(package_manager)"
    packages="$(grep -v '^[[:space:]]*$' "$PACKAGE_LIST" || true)"
    [ -n "$packages" ] || { say "$(t deps_none_installed)"; return 0; }

    present=""
    for pkg in $packages; do
        case "$manager" in
            arch) pacman -Qq "$pkg" >/dev/null 2>&1 && present="$present $pkg" ;;
            debian) dpkg -s "$pkg" >/dev/null 2>&1 && present="$present $pkg" ;;
            fedora) rpm_installed "$pkg" && present="$present $pkg" ;;
        esac
    done
    present="${present# }"
    [ -n "$present" ] || { say "$(t deps_present_none)"; rm -f "$PACKAGE_LIST"; return 0; }

    say "$(t deps_will_remove "$present")"
    say "$(t deps_rm_hint)"
    ask "$(t confirm_deps)" n || { say "$(t cancelled)"; return 0; }
    ensure_sudo || return 1
    case "$manager" in
        arch) root_run pacman -Rns --noconfirm $present ;;
        debian)
            root_run apt-get remove -y $present
            root_run apt-get autoremove -y
            ;;
        fedora)
            root_run "$(dnf_cmd)" remove -y $present
            root_run "$(dnf_cmd)" autoremove -y
            ;;
    esac
    rm -f "$PACKAGE_LIST"
    say "$(t deps_removed)"
}
require_artifacts() {
    local missing=0 artifact
    for artifact in Launcher.jar blockpulse-launcher-ui.jar; do
        if [ ! -f "$BASE_DIR/app/$artifact" ]; then
            err "$(t artifacts_missing "$artifact")"
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        err ""
        t artifacts_help "$BASE_DIR" >&2
        err ""
        return 1
    fi
    if [ ! -d "$BASE_DIR/app/profiles" ] || [ -z "$(find "$BASE_DIR/app/profiles" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null)" ]; then
        err "$(t artifacts_no_profiles)"
    fi
    return 0
}
copy_files() {
    mkdir -p "$APP_DIR" "$APP_DIR/profiles" "$BIN_DIR"
    put_file 644 "$BASE_DIR/app/Launcher.jar" "$APP_DIR/Launcher.jar"
    put_file 644 "$BASE_DIR/app/blockpulse-launcher-ui.jar" "$APP_DIR/blockpulse-launcher-ui.jar"
    if [ -d "$BASE_DIR/app/profiles" ]; then
        local profile
        for profile in "$BASE_DIR/app/profiles"/*.json; do
            [ -f "$profile" ] || continue
            put_file 644 "$profile" "$APP_DIR/profiles/$(basename "$profile")"
        done
    fi
    put_file 755 "$BASE_DIR/blockpulse-launcher" "$INSTALL_DIR/blockpulse-launcher"
    rm -rf "$INSTALL_DIR/decompiled" "$INSTALL_DIR/patch" "$INSTALL_DIR/packaging" "$INSTALL_DIR/.git"
    rm -f "$INSTALL_DIR/README.md" "$INSTALL_DIR/PKGBUILD" "$INSTALL_DIR/build.sh" \
          "$INSTALL_DIR/run.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/BUILD_LINUX.md" \
          "$INSTALL_DIR/BUILD_TAB_FIX.txt" "$INSTALL_DIR/blockpulse-launcher.png"
    chown_user "$INSTALL_DIR"
}
apply_shortcuts() {
    if [ "${ADD_COMMAND:-1}" = 1 ]; then
        ln -sfn "$INSTALL_DIR/blockpulse-launcher" "$LINK_FILE"
        chown_user "$LINK_FILE"
    else
        rm -f "$LINK_FILE"
    fi
    if [ "${ADD_DESKTOP:-1}" = 1 ]; then
        write_desktop
        chown_user "$DESKTOP_DIR" "$ICON_DIR"
    else
        remove_desktop
    fi
}
show_status() {
    if javafx_status; then
        say "$(t javafx_ready "$JAVAFX_STATUS_TEXT")"
        return 0
    fi
    case "$JAVAFX_STATUS_KIND" in
        old)
            say "$(t javafx_old "$JAVAFX_STATUS_TEXT")"
            say ""
            say "$(t javafx_old_hint)"
            ;;
        *) say "$(t javafx_none "$JAVAFX_STATUS_TEXT")" ;;
    esac
    return 0
}
check_runtime() {
    javafx_status || true
    return 0
}
install_launcher() {
    local manager="$1"
    require_artifacts || return 1

    reset_probe_cache
    ADD_COMMAND=1
    ADD_DESKTOP=1
    ask "$(t add_command_q)" y || ADD_COMMAND=0
    ask "$(t add_desktop_q)" y || ADD_DESKTOP=0

    mkdir -p "$CONF_DIR"
    printf '%s\n' "$LANG_CODE" >"$LANGUAGE_FILE"
    chmod 644 "$LANGUAGE_FILE" 2>/dev/null || true
    chown_user "$CONF_DIR"

    phase 4
    run_step "$(t step_verify)" require_artifacts || return 1
    run_step "$(t step_copy)" copy_files || return 1
    run_step "$(t step_shortcuts)" apply_shortcuts || return 1
    run_step "$(t step_status)" check_runtime || true

    say ""
    say "${C_GREEN}$(t installed "$INSTALL_DIR")${C_RESET}"
    say "$(t version_line "$PORT_VERSION" "$LAUNCHER_VERSION")"
    show_status
    if [ -L "$LINK_FILE" ]; then
        say "$(t command_path "$LINK_FILE")"
    fi
    if [ -f "$DESKTOP_FILE" ]; then
        say "$(t menu_path "$DESKTOP_FILE")"
    fi
    say "$(t log_path "$INSTALL_LOG")"
    return 0
}
usage() {
    say "${C_BOLD}$(t usage_title "$PORT_VERSION" "$LAUNCHER_VERSION")${C_RESET}"
    say ""
    say "${C_BOLD}$(t usage_install_hdr)${C_RESET}"
    say "$(t usage_install)"
    say ""
    say "${C_BOLD}$(t usage_remove_hdr)${C_RESET}"
    say "$(t usage_uninstall)"
    say "$(t usage_keep)"
    say "$(t usage_all)"
    say ""
    say "${C_BOLD}$(t usage_output_hdr)${C_RESET}"
    say "$(t usage_quiet)"
    say "$(t usage_lang)"
    say "$(t usage_yes)"
    say "$(t usage_debug)"
    say "$(t usage_dry)"
    say ""
    say "${C_BOLD}$(t usage_other_hdr)${C_RESET}"
    say "$(t usage_version)"
    say "$(t usage_help)"
    say ""
    say "${C_DIM}$(t usage_examples)${C_RESET}"
    say "  ./install.sh --quiet --lang en"
    say "  ./install.sh --uninstall --keep-game"
    say "  ./install.sh --dry-run"
}

MODE=install
KEEP_GAME=0
LANG_ARG=''
SHOW_HELP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h) SHOW_HELP=1 ;;
        --version|-V) MODE=version ;;
        --uninstall) MODE=uninstall ;;
        --uninstall-all) MODE=uninstall-all ;;
        --keep-game) KEEP_GAME=1 ;;
        --debug) DEBUG=1 ;;
        --quiet|-q) QUIET=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --lang=*) LANG_ARG="${1#--lang=}" ;;
        --lang)
            shift
            [ $# -gt 0 ] && LANG_ARG="$1" || LANG_ARG=''
            ;;
        '') ;;
        *) BAD_ARG="$1" ;;
    esac
    shift
done
case "${LANG_ARG:-}" in
    uk|ua|UK|UA) LANG_ARG=uk ;;
    ru|RU) LANG_ARG=ru ;;
    en|EN) LANG_ARG=en ;;
    *) LANG_ARG='' ;;
esac

choose_language
[ -z "$LANG_CODE" ] && LANG_CODE=en
if [ -n "${BAD_ARG:-}" ]; then
    err_color "$(t unknown_arg "$BAD_ARG")"
    say ""
    usage
    exit 2
fi
if [ "$SHOW_HELP" = 1 ]; then
    usage
    exit 0
fi
if [ "$MODE" = version ]; then
    say "$(t version_port "$PORT_VERSION")"
    say "$(t version_launcher "$LAUNCHER_VERSION")"
    exit 0
fi

INSTALL_LOG="$STATE_DIR/install.log"
RUN_LOG="$(mktemp "${TMPDIR:-/tmp}/blockpulse-install.XXXXXX")"
trap 'rm -f "$RUN_LOG"' EXIT
if [ "$MODE" = install ] && [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$CONF_DIR" "$STATE_DIR" 2>/dev/null || true
    chmod 700 "$CONF_DIR" 2>/dev/null || true
    chown_user "$CONF_DIR" "$STATE_DIR"
    rotate_log
    : >>"$INSTALL_LOG"
fi

say "${C_BOLD}$(t usage_title "$PORT_VERSION" "$LAUNCHER_VERSION")${C_RESET}"
say "${C_DIM}$INSTALL_DIR${C_RESET}"
note "${C_DIM}$(t help_hint)${C_RESET}"

if [ "$MODE" != install ]; then
    [ "$MODE" = uninstall-all ] && uninstall_dependencies
    uninstall_launcher "$KEEP_GAME"
    exit 0
fi

manager="$(package_manager)"
if [ "$manager" = unsupported ]; then
    err_color "$(t unsupported)"
    exit 1
fi
require_artifacts || exit 1

java_now="$(java21_path 2>/dev/null || true)"
fx_now="$(javafx_path 2>/dev/null || true)"
missing_dependencies "$manager"

say ""
say "${C_BOLD}$(t summary)${C_RESET}"
say "$(t sys_line "$(os_name) [$manager]")"
say "$(t dir_line "$INSTALL_DIR")"
say "$(t java_line "${java_now:-$(t not_found)}")"
if [ "$fx_now" = bundled ]; then
    say "$(t fx_line "JavaFX (bundled with the JDK)")"
elif [ -n "${fx_now:-}" ]; then
    say "$(t fx_line "$fx_now")"
else
    say "$(t fx_line "$(t not_found)")"
fi
if [ "${#DEP_MISSING[@]}" -gt 0 ]; then
    say "$(t missing_line "${DEP_MISSING[*]}")"
fi
say ""

if [ "$DRY_RUN" = 1 ]; then
    say "$(t dry_run_done)"
    exit 0
fi

if ! ask "$(t continue_q)" y; then
    say "$(t cancelled)"
    exit 0
fi

if [ "${#DEP_MISSING[@]}" -gt 0 ]; then
    if ask "$(t deps_ask)" y; then
        [ "$(id -u)" -ne 0 ] && ! has sudo && { err_color "$(t no_sudo)"; exit 1; }
        ensure_sudo || exit 1
        phase 1
        run_step "$(t step_deps)" install_dependencies "$manager" || true
        reset_probe_cache
        missing_dependencies "$manager"
        if [ "${#DEP_MISSING[@]}" -gt 0 ]; then
            err_color "$(t deps_incomplete "${DEP_MISSING[*]}")"
            exit 1
        fi
    else
        note "$(t deps_skipped)"
    fi
fi

if [ -e "$INSTALL_DIR" ]; then
    if ! ask "$(t dir_exists_q)" y; then
        exit 0
    fi
fi

if ! install_launcher "$manager"; then
    exit 1
fi

say ""
choice='3'
if [ "$TTY" = 1 ] && [ "$ASSUME_YES" = 0 ]; then
    say "${C_BOLD}$(t menu_title)${C_RESET}"
    say "$(t menu_launch)"
    say "$(t menu_diag)"
    say "$(t menu_exit)"
    printf '%s' "$(t menu_choice)"
    read -r choice || true
fi
case "${choice:-3}" in
    1)
        if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            user_run "$INSTALL_DIR/blockpulse-launcher"
        else
            "$INSTALL_DIR/blockpulse-launcher"
        fi
        ;;
    2) "$INSTALL_DIR/blockpulse-launcher" --diagnose ;;
    *) exit 0 ;;
esac
