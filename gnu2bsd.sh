#!/bin/bash

BOLD=$(tput bold 2>/dev/null || echo "")
BLU=$(tput setaf 4 2>/dev/null || echo "")
GRN=$(tput setaf 2 2>/dev/null || echo "")
YEL=$(tput setaf 3 2>/dev/null || echo "")
RED=$(tput setaf 1 2>/dev/null || echo "")
RST=$(tput sgr0 2>/dev/null || echo "")

hdr() { printf '\n%s%s==== %s ====%s\n' "$BOLD" "$BLU" "$1" "$RST"; }
ok() {
	printf '  %s[ ok ]%s   %s\n\n' "$GRN" "$RST" "$1"
	return 0
}
skip() {
	printf '  %s[skip]%s   %s\n\n' "$YEL" "$RST" "$1"
	return 0
}
na() { printf '  %s[ na ]%s   %s\n' "$BLU" "$RST" "$1"; }
info() { printf '  %s[info]%s   %s\n' "$BLU" "$RST" "$1"; }
err() {
	printf '%s%sERROR:%s %s\n' "$BOLD" "$RED" "$RST" "$1" >&2
	return 1
}

persist_line() {
	local f="$1" pat="$2" line="$3"
	touch "$f" 2>/dev/null || return 1
	grep -Fq "$pat" "$f" 2>/dev/null && return 2
	printf '%s\n' "$line" >>"$f" || return 1
	return 0
}

hdr "Checking Homebrew Status"
brew_path() {
	if [ -x /opt/homebrew/bin/brew ]; then
		echo /opt/homebrew/bin/brew
	elif [ -x /usr/local/bin/brew ]; then
		echo /usr/local/bin/brew
	elif command -v brew >/dev/null 2>&1; then
		command -v brew
	fi
}

BREW="$(brew_path)"
if [ -n "$BREW" ]; then
	eval "$("$BREW" shellenv)"
	ok "Homebrew present ($BREW)"
else
	info "Installing Homebrew (non-interactive)..."
	if NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
		BREW="$(brew_path)"
		[ -n "$BREW" ] && eval "$("$BREW" shellenv)"
		ok "Homebrew installed"
	else
		skip "Homebrew install failed (needs CLT + network); re-run later"
	fi
fi

if [ -n "${BREW:-}" ] && [ -x "$BREW" ]; then
	SHELLENV_LINE="eval \"\$(${BREW} shellenv)\""
	persist_line "$HOME/.zprofile" 'brew shellenv' "$SHELLENV_LINE"
	rc=$?
	case "$rc" in
	0) ok "Added brew shellenv to ~/.zprofile" ;;
	2) ok "brew shellenv already in ~/.zprofile" ;;
	*) skip "Could not update ~/.zprofile" ;;
	esac

	"$BREW" analytics off >/dev/null 2>&1 && ok "Homebrew analytics disabled" || skip "Homebrew analytics toggle"

fi

hdr "Linuxifying..."

BREW_FORMULAE=(
	coreutils findutils gnu-sed gnu-tar grep readline gettext
	diffutils gzip ed less make bash gpatch xz iproute2mac
	git rsync vim emacs nano screen watch wget wdiff
	m4 bison flex openssh libressl unzip zlib sqlite gawk
	openssl gnutls file-formula binutils gnu-indent gnu-getopt gnu-time gnu-which
)

if [ -n "${BREW:-}" ] && [ -x "$BREW" ]; then
	installed_formulae=$("$BREW" list --formula -1 2>/dev/null)

	for formula in "${BREW_FORMULAE[@]}"; do
		if echo "$installed_formulae" | grep -Eq "^${formula}(@.*)?$"; then
			skip "$formula is already installed."
		else
			info "Installing formula: $formula"
			if "$BREW" install "$formula" &>/dev/null; then
				ok "Successfully installed $formula"
			else
				err "Failed to install $formula"
			fi
		fi
	done
else
	err "Homebrew not found. Skipping formulae installation."
fi

FISH_DIR="$HOME/.config/fish"
FISH_CONFIG="$FISH_DIR/config.fish"
ZPROFILE="$HOME/.zprofile"

touch "$ZPROFILE"

if ! grep -q "linuxify" "$ZPROFILE" 2>/dev/null; then
	cat <<'GNUBLOCK' >>"$ZPROFILE"

# >>> linuxify >>>
# ==============================================================================
# GNU-to-BSD / Linux-to-macOS Compatibility Layer for macOS
#
# Rule:
#   308 = close-enough / safe redirect, then execute
#   301 = conceptual / approximate / risky redirect, explain only
# ==============================================================================

# Only run in interactive shells.
case "$-" in
    *i*) ;;
    *) return 0 2>/dev/null || exit 0 ;;
esac

# Only run on macOS.
[[ "${OSTYPE:-}" == darwin* ]] || return 0 2>/dev/null || exit 0

# ------------------------------------------------------------------------------
# 0. Core helpers
# ------------------------------------------------------------------------------

__g2b_have() {
    command -v "$1" >/dev/null 2>&1
}

__g2b_brew_bin() {
    if [ -n "${HOMEBREW_PREFIX:-}" ] && [ -x "$HOMEBREW_PREFIX/bin/brew" ]; then
        printf '%s\n' "$HOMEBREW_PREFIX/bin/brew"
        elif [ -x /opt/homebrew/bin/brew ]; then
        printf '%s\n' /opt/homebrew/bin/brew
        elif [ -x /usr/local/bin/brew ]; then
        printf '%s\n' /usr/local/bin/brew
        elif command -v brew >/dev/null 2>&1; then
        command -v brew
    else
        return 1
    fi
}

__g2b_brew() {
    local b
    b="$(__g2b_brew_bin)" || return 127
    "$b" "$@"
}

__g2b_brew_or_die() {
    if ! __g2b_brew_bin >/dev/null 2>&1; then
        printf '\033[1;31mgnu2bsd target missing:\033[0m Homebrew is not installed or not in PATH.\n' >&2
        printf 'Install Homebrew first, then retry.\n' >&2
        return 127
    fi
}

__g2b_redirect_msg() {
    local code="$1"
    local old="$2"
    local new="$3"

    case "$code" in
        308)
            printf '\033[1;32m308 Permanent Redirect\033[0m: command "%s" permanently moved to "%s"\n' "$old" "$new" >&2
            printf '\033[1;36mredirecting to:\033[0m %s\n' "$new" >&2
        ;;
        301)
            printf '\033[1;33m301 Moved Permanently\033[0m: command "%s" permanently moved to "%s"\n' "$old" "$new" >&2
            printf '\033[1;31mnot auto-executing:\033[0m mapping is conceptual, approximate, or not safely 1:1 compatible\n' >&2
            printf '\033[1;36mBSD/macOS equivalent:\033[0m %s\n' "$new" >&2
        ;;
        *)
            printf '\033[1;33m%s Redirect\033[0m: command "%s" moved to "%s"\n' "$code" "$old" "$new" >&2
        ;;
    esac
}

# 301 = teach only, do not execute.
__g2b_301() {
    local old="$1"
    local new="$2"
    __g2b_redirect_msg 301 "$old" "$new"
}

# 308 = teach, then execute.
__g2b_308() {
    local old="$1"
    local new="$2"
    shift 2

    __g2b_redirect_msg 308 "$old" "$new"
    "$@"
}

__g2b_pkg_clean() {
    __G2B_PKG_ARGS=()

    local a
    for a in "$@"; do
        case "$a" in
            -y | --yes | --assume-yes | --noconfirm | --needed | --no-install-recommends | --best | --allowerasing | --skip-broken | --refresh)
            ;;
            --)
            ;;
            *)
                __G2B_PKG_ARGS+=("$a")
            ;;
        esac
    done
}

__g2b_svc_name() {
    local s="${1:-}"
    s="${s%.service}"
    printf '%s' "$s"
}

__g2b_map_if_missing() {
    local cmd="$1"
    local target="$2"

    if ! __g2b_have "$cmd"; then
        alias "$cmd"="$target"
    fi
}

__g2b_note() {
    printf '\033[1;36mgnu2bsd:\033[0m %s\n' "$*" >&2
}

# ------------------------------------------------------------------------------
# 1. Homebrew + GNU path/man/info/build-env injection
# ------------------------------------------------------------------------------

__g2b_colon_prepend() {

    local _g2b_var="$1"
    local _g2b_dir="$2"
    local _g2b_cur
    local _g2b_new

    [ -n "$_g2b_var" ] || return 0
    [ -n "$_g2b_dir" ] || return 0
    [ -d "$_g2b_dir" ] || return 0

    eval "_g2b_cur=\${$_g2b_var:-}"

    case ":$_g2b_cur:" in
        *":$_g2b_dir:"*) return 0 ;;
    esac

    if [ -n "$_g2b_cur" ]; then
        _g2b_new="$_g2b_dir:$_g2b_cur"
    else
        _g2b_new="$_g2b_dir"
    fi

    export "$_g2b_var=$_g2b_new"
}

__g2b_colon_prepend_keep_default() {
    local _g2b_var="$1"
    local _g2b_dir="$2"
    local _g2b_cur
    local _g2b_new

    [ -n "$_g2b_var" ] || return 0
    [ -n "$_g2b_dir" ] || return 0
    [ -d "$_g2b_dir" ] || return 0

    eval "_g2b_cur=\${$_g2b_var:-}"

    case ":$_g2b_cur:" in
        *":$_g2b_dir:"*) return 0 ;;
    esac

    if [ -n "$_g2b_cur" ]; then
        _g2b_new="$_g2b_dir:$_g2b_cur"
    else
        _g2b_new="$_g2b_dir:"
    fi

    export "$_g2b_var=$_g2b_new"
}

__g2b_space_prepend() {
    local _g2b_var="$1"
    local _g2b_item="$2"
    local _g2b_cur
    local _g2b_new

    [ -n "$_g2b_var" ] || return 0
    [ -n "$_g2b_item" ] || return 0

    eval "_g2b_cur=\${$_g2b_var:-}"

    case " $_g2b_cur " in
        *" $_g2b_item "*) return 0 ;;
    esac

    if [ -n "$_g2b_cur" ]; then
        _g2b_new="$_g2b_item $_g2b_cur"
    else
        _g2b_new="$_g2b_item"
    fi

    export "$_g2b_var=$_g2b_new"
}

__g2b_add_gnubin_formula() {
    local _g2b_formula
    local _g2b_opt

    for _g2b_formula in "$@"; do
        _g2b_opt="$BREW_HOME/opt/$_g2b_formula"

        __g2b_colon_prepend PATH "$_g2b_opt/libexec/gnubin"
        __g2b_colon_prepend_keep_default MANPATH "$_g2b_opt/libexec/gnuman"
    done
}

__g2b_add_opt_bin_formula() {
    local _g2b_formula
    local _g2b_opt

    for _g2b_formula in "$@"; do
        _g2b_opt="$BREW_HOME/opt/$_g2b_formula"

        __g2b_colon_prepend PATH "$_g2b_opt/bin"
        __g2b_colon_prepend_keep_default MANPATH "$_g2b_opt/share/man"
        __g2b_colon_prepend_keep_default INFOPATH "$_g2b_opt/share/info"
    done
}

__g2b_add_build_formula() {
    local _g2b_formula
    local _g2b_opt

    for _g2b_formula in "$@"; do
        _g2b_opt="$BREW_HOME/opt/$_g2b_formula"

        __g2b_colon_prepend PATH "$_g2b_opt/bin"
        __g2b_colon_prepend_keep_default MANPATH "$_g2b_opt/share/man"
        __g2b_colon_prepend_keep_default INFOPATH "$_g2b_opt/share/info"

        [ -d "$_g2b_opt/lib" ] && __g2b_space_prepend LDFLAGS "-L$_g2b_opt/lib"
        [ -d "$_g2b_opt/include" ] && __g2b_space_prepend CPPFLAGS "-I$_g2b_opt/include"
        [ -d "$_g2b_opt/lib/pkgconfig" ] && __g2b_colon_prepend PKG_CONFIG_PATH "$_g2b_opt/lib/pkgconfig"
    done
}

if [ -z "${HOMEBREW_PREFIX:-}" ]; then
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

BREW_HOME="${HOMEBREW_PREFIX:-}"

if [ -z "$BREW_HOME" ] && command -v brew >/dev/null 2>&1; then
    BREW_HOME="$(brew --prefix 2>/dev/null)"
fi

if [ -n "$BREW_HOME" ] && [ -d "$BREW_HOME" ]; then
    export HOMEBREW_PREFIX="$BREW_HOME"

    __g2b_colon_prepend PATH "$BREW_HOME/bin"
    __g2b_colon_prepend PATH "$BREW_HOME/sbin"
    __g2b_colon_prepend_keep_default MANPATH "$BREW_HOME/share/man"
    __g2b_colon_prepend_keep_default INFOPATH "$BREW_HOME/share/info"

    __g2b_colon_prepend PATH "$HOME/.local/bin"

    __g2b_add_gnubin_formula \
    coreutils \
    make \
    ed \
    findutils \
    gnu-indent \
    gnu-sed \
    gnu-tar \
    gnu-which \
    grep \
    gawk \
    gnu-time \
    diffutils

    __g2b_add_opt_bin_formula \
    gnu-getopt \
    m4 \
    file-formula \
    unzip

    __g2b_add_build_formula \
    flex \
    bison \
    libressl \
    openssl@3 \
    readline \
    sqlite \
    gettext \
    zlib \
    xz
fi

# Zsh-only duplicate cleanup. Harmlessly skipped by Bash.
if [ -n "${ZSH_VERSION:-}" ]; then
    typeset -U path PATH manpath MANPATH infopath INFOPATH 2>/dev/null
fi

export PATH MANPATH INFOPATH LDFLAGS CPPFLAGS PKG_CONFIG_PATH
unset BREW_HOME

# ------------------------------------------------------------------------------
# 2. Package management handlers
# ------------------------------------------------------------------------------

__g2b_brew_update_upgrade() {
    __g2b_brew update && __g2b_brew upgrade
}

__g2b_apt() {
    __g2b_brew_or_die || return $?

    while [[ "${1:-}" == -* ]]; do
        case "$1" in
            -y | --yes | --assume-yes) shift ;;
            *) break ;;
        esac
    done

    local sub="${1:-}"
    shift || true

    case "$sub" in
        install)
            __g2b_pkg_clean "$@"
            __g2b_308 "apt install ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
        ;;
        reinstall)
            __g2b_pkg_clean "$@"
            __g2b_308 "apt reinstall ${__G2B_PKG_ARGS[*]}" "brew reinstall ${__G2B_PKG_ARGS[*]}" __g2b_brew reinstall "${__G2B_PKG_ARGS[@]}"
        ;;
        remove)
            __g2b_pkg_clean "$@"
            __g2b_308 "apt remove ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
        ;;
        purge)
            __g2b_pkg_clean "$@"
            __g2b_308 "apt purge ${__G2B_PKG_ARGS[*]}" "brew uninstall --zap ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall --zap "${__G2B_PKG_ARGS[@]}"
        ;;
        update)
            __g2b_308 "apt update" "brew update" __g2b_brew update
        ;;
        upgrade | dist-upgrade | full-upgrade)
            __g2b_308 "apt $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
        ;;
        autoremove)
            __g2b_308 "apt autoremove" "brew autoremove" __g2b_brew autoremove
        ;;
        autoclean | clean)
            __g2b_308 "apt $sub" "brew cleanup" __g2b_brew cleanup
        ;;
        search)
            __g2b_308 "apt search $*" "brew search $*" __g2b_brew search "$@"
        ;;
        show | info | policy)
            __g2b_308 "apt $sub $*" "brew info $*" __g2b_brew info "$@"
        ;;
        list)
            __g2b_308 "apt list $*" "brew list $*" __g2b_brew list "$@"
        ;;
        edit-sources)
            __g2b_301 "apt edit-sources" "brew tap / brew untap"
            printf 'Homebrew uses taps instead of apt source files.\n' >&2
            printf 'Examples:\n  brew tap owner/repo\n  brew untap owner/repo\n' >&2
        ;;
        *)
            __g2b_301 "apt $sub $*" "brew help"
            printf 'Run manually if intended: brew help\n' >&2
        ;;
    esac
}

__g2b_apt_cache() {
    __g2b_brew_or_die || return $?

    local sub="${1:-}"
    shift || true

    case "$sub" in
        search)
            __g2b_308 "apt-cache search $*" "brew search $*" __g2b_brew search "$@"
        ;;
        show | showpkg | policy)
            __g2b_308 "apt-cache $sub $*" "brew info $*" __g2b_brew info "$@"
        ;;
        *)
            __g2b_301 "apt-cache $sub $*" "brew search / brew info"
        ;;
    esac
}

__g2b_add_apt_repository() {
    __g2b_brew_or_die || return $?
    __g2b_301 "add-apt-repository $*" "brew tap $*"
    printf 'Homebrew taps are not always equivalent to apt repositories.\n' >&2
    printf 'Run manually if intended: brew tap %s\n' "$*" >&2
}

__g2b_pacman() {
    __g2b_brew_or_die || return $?

    local sub="${1:-}"
    shift || true

    case "$sub" in
        -S | --sync)
            __g2b_pkg_clean "$@"
            __g2b_308 "pacman -S ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
        ;;
        -Syu | -Syyu | -Syuu | -Su)
            __g2b_308 "pacman $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
        ;;
        -Sy)
            __g2b_308 "pacman -Sy" "brew update" __g2b_brew update
        ;;
        -R | -Rs | -Rns)
            __g2b_pkg_clean "$@"
            __g2b_308 "pacman $sub ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
        ;;
        -Ss)
            __g2b_308 "pacman -Ss $*" "brew search $*" __g2b_brew search "$@"
        ;;
        -Si | -Qi)
            __g2b_308 "pacman $sub $*" "brew info $*" __g2b_brew info "$@"
        ;;
        -Q | -Qe)
            __g2b_308 "pacman $sub" "brew list" __g2b_brew list
        ;;
        -Qs)
            __g2b_redirect_msg 308 "pacman -Qs $*" "brew list | grep $*"
            __g2b_brew list | grep "$*" || true
        ;;
        -Ql)
            __g2b_308 "pacman -Ql $*" "brew list --verbose $*" __g2b_brew list --verbose "$@"
        ;;
        -Qdt)
            __g2b_308 "pacman -Qdt" "brew autoremove" __g2b_brew autoremove
        ;;
        -Sc | -Scc)
            __g2b_308 "pacman $sub" "brew cleanup" __g2b_brew cleanup
        ;;
        *)
            __g2b_301 "pacman $sub $*" "brew help"
            printf 'Run manually if intended: brew help\n' >&2
        ;;
    esac
}

__g2b_yay() {
    __g2b_brew_or_die || return $?
    __g2b_308 "yay $*" "brew $*" __g2b_brew "$@"
}

__g2b_paru() {
    __g2b_brew_or_die || return $?
    __g2b_308 "paru $*" "brew $*" __g2b_brew "$@"
}

__g2b_dnf() {
    __g2b_brew_or_die || return $?

    while [[ "${1:-}" == -* ]]; do
        case "$1" in
            -y | --assumeyes | --best | --allowerasing | --skip-broken) shift ;;
            *) break ;;
        esac
    done

    local sub="${1:-}"
    shift || true

    case "$sub" in
        install)
            __g2b_pkg_clean "$@"
            __g2b_308 "dnf install ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
        ;;
        reinstall)
            __g2b_pkg_clean "$@"
            __g2b_308 "dnf reinstall ${__G2B_PKG_ARGS[*]}" "brew reinstall ${__G2B_PKG_ARGS[*]}" __g2b_brew reinstall "${__G2B_PKG_ARGS[@]}"
        ;;
        remove | erase)
            __g2b_pkg_clean "$@"
            __g2b_308 "dnf $sub ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
        ;;
        update | upgrade)
            __g2b_308 "dnf $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
        ;;
        check-update | makecache)
            __g2b_308 "dnf $sub" "brew update" __g2b_brew update
        ;;
        search)
            __g2b_308 "dnf search $*" "brew search $*" __g2b_brew search "$@"
        ;;
        info)
            __g2b_308 "dnf info $*" "brew info $*" __g2b_brew info "$@"
        ;;
        list)
            __g2b_308 "dnf list $*" "brew list $*" __g2b_brew list "$@"
        ;;
        autoremove)
            __g2b_308 "dnf autoremove" "brew autoremove" __g2b_brew autoremove
        ;;
        clean)
            __g2b_308 "dnf clean $*" "brew cleanup" __g2b_brew cleanup
        ;;
        groupinstall | group)
            __g2b_301 "dnf $sub $*" "brew bundle / Brewfile"
            printf 'Homebrew has no true dnf group equivalent. Use a Brewfile for grouped installs.\n' >&2
        ;;
        *)
            __g2b_301 "dnf $sub $*" "brew help"
            printf 'Run manually if intended: brew help\n' >&2
        ;;
    esac
}

__g2b_zypper() {
    __g2b_brew_or_die || return $?

    while [[ "${1:-}" == -* ]]; do
        case "$1" in
            -n | --non-interactive) shift ;;
            *) break ;;
        esac
    done

    local sub="${1:-}"
    shift || true

    case "$sub" in
        in | install)
            __g2b_pkg_clean "$@"
            __g2b_308 "zypper install ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
        ;;
        rm | remove)
            __g2b_pkg_clean "$@"
            __g2b_308 "zypper remove ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
        ;;
        up | update | dup)
            __g2b_308 "zypper $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
        ;;
        ref | refresh)
            __g2b_308 "zypper refresh" "brew update" __g2b_brew update
        ;;
        se | search)
            __g2b_308 "zypper search $*" "brew search $*" __g2b_brew search "$@"
        ;;
        info)
            __g2b_308 "zypper info $*" "brew info $*" __g2b_brew info "$@"
        ;;
        clean)
            __g2b_308 "zypper clean" "brew cleanup" __g2b_brew cleanup
        ;;
        *)
            __g2b_301 "zypper $sub $*" "brew help"
            printf 'Run manually if intended: brew help\n' >&2
        ;;
    esac
}

__g2b_apk() {
    __g2b_brew_or_die || return $?

    local sub="${1:-}"
    shift || true

    case "$sub" in
        add)
            __g2b_pkg_clean "$@"
            __g2b_308 "apk add ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
        ;;
        del | delete)
            __g2b_pkg_clean "$@"
            __g2b_308 "apk del ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
        ;;
        update)
            __g2b_308 "apk update" "brew update" __g2b_brew update
        ;;
        upgrade)
            __g2b_308 "apk upgrade" "brew upgrade" __g2b_brew upgrade
        ;;
        search)
            __g2b_308 "apk search $*" "brew search $*" __g2b_brew search "$@"
        ;;
        info)
            __g2b_308 "apk info $*" "brew info $*" __g2b_brew info "$@"
        ;;
        cache)
            __g2b_308 "apk cache $*" "brew cleanup" __g2b_brew cleanup
        ;;
        *)
            __g2b_301 "apk $sub $*" "brew help"
            printf 'Run manually if intended: brew help\n' >&2
        ;;
    esac
}

__g2b_xbps_install() {
    __g2b_brew_or_die || return $?

    if [ "${1:-}" = "-Syu" ] || [ "${1:-}" = "-Su" ]; then
        __g2b_308 "xbps-install $*" "brew update && brew upgrade" __g2b_brew_update_upgrade
    else
        __g2b_pkg_clean "$@"
        __g2b_308 "xbps-install ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
    fi
}

__g2b_xbps_remove() {
    __g2b_brew_or_die || return $?
    __g2b_pkg_clean "$@"
    __g2b_308 "xbps-remove ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
}

__g2b_emerge() {
    __g2b_brew_or_die || return $?

    case "${1:-}" in
        --sync)
            __g2b_308 "emerge --sync" "brew update" __g2b_brew update
        ;;
        -C | --unmerge)
            shift
            __g2b_pkg_clean "$@"
            __g2b_308 "emerge --unmerge ${__G2B_PKG_ARGS[*]}" "brew uninstall ${__G2B_PKG_ARGS[*]}" __g2b_brew uninstall "${__G2B_PKG_ARGS[@]}"
        ;;
        -s | --search)
            shift
            __g2b_308 "emerge --search $*" "brew search $*" __g2b_brew search "$@"
        ;;
        *)
            __g2b_pkg_clean "$@"
            __g2b_308 "emerge ${__G2B_PKG_ARGS[*]}" "brew install ${__G2B_PKG_ARGS[*]}" __g2b_brew install "${__G2B_PKG_ARGS[@]}"
        ;;
    esac
}

__g2b_snap() {
    __g2b_brew_or_die || return $?

    local sub="${1:-}"
    shift || true

    case "$sub" in
        install)
            __g2b_pkg_clean "$@"
            __g2b_301 "snap install ${__G2B_PKG_ARGS[*]}" "brew install --cask ${__G2B_PKG_ARGS[*]} OR brew install ${__G2B_PKG_ARGS[*]}"
            printf 'Snap names often do not match Homebrew formula/cask names.\n' >&2
            printf 'Try manually: brew search %s\n' "${__G2B_PKG_ARGS[*]}" >&2
        ;;
        remove | purge)
            __g2b_pkg_clean "$@"
            __g2b_301 "snap $sub ${__G2B_PKG_ARGS[*]}" "brew uninstall --cask ${__G2B_PKG_ARGS[*]} OR brew uninstall ${__G2B_PKG_ARGS[*]}"
        ;;
        list)
            __g2b_301 "snap list" "brew list --cask && brew list"
        ;;
        find | search)
            __g2b_301 "snap $sub $*" "brew search --cask $*"
        ;;
        *)
            __g2b_301 "snap $sub $*" "brew --cask"
        ;;
    esac
}

__g2b_flatpak() {
    __g2b_brew_or_die || return $?

    local sub="${1:-}"
    shift || true

    local last=""
    for last in "$@"; do :; done

    case "$sub" in
        install)
            if [ -z "$last" ]; then
                __g2b_301 "flatpak install" "brew search --cask <name>"
                return 64
            fi
            __g2b_301 "flatpak install $*" "brew install --cask $last"
            printf 'Flatpak IDs often do not match Homebrew cask names.\n' >&2
            printf 'Try manually: brew search --cask %s\n' "$last" >&2
        ;;
        uninstall | remove)
            if [ -z "$last" ]; then
                __g2b_301 "flatpak $sub" "brew uninstall --cask <name>"
                return 64
            fi
            __g2b_301 "flatpak $sub $*" "brew uninstall --cask $last"
        ;;
        search)
            __g2b_301 "flatpak search $*" "brew search --cask $*"
        ;;
        list)
            __g2b_301 "flatpak list" "brew list --cask"
        ;;
        *)
            __g2b_301 "flatpak $sub $*" "brew --cask"
        ;;
    esac
}

# ------------------------------------------------------------------------------
# 4. Service management: systemd/service -> launchd/Homebrew services
# ------------------------------------------------------------------------------

__g2b_brew_services_prefix() {
    if [ "${GNU2BSD_SUDO:-}" = "1" ]; then
        printf 'sudo brew services'
    else
        printf 'brew services'
    fi
}

__g2b_brew_services_run() {
    if [ "${GNU2BSD_SUDO:-}" = "1" ]; then
        command sudo "$(__g2b_brew_bin)" services "$@"
    else
        __g2b_brew services "$@"
    fi
}

__g2b_brew_services_status() {
    local svc="$1"

    if [ "${GNU2BSD_SUDO:-}" = "1" ]; then
        command sudo "$(__g2b_brew_bin)" services list | grep "$svc" || true
    else
        __g2b_brew services list | grep "$svc" || true
    fi
}

__g2b_brew_services_is_active() {
    local svc="$1"

    if [ "${GNU2BSD_SUDO:-}" = "1" ]; then
        command sudo "$(__g2b_brew_bin)" services list | grep "$svc" | grep started >/dev/null
    else
        __g2b_brew services list | grep "$svc" | grep started >/dev/null
    fi
}

__g2b_systemctl() {
    __g2b_brew_or_die || return $?

    if [ "${1:-}" = "--user" ] || [ "${1:-}" = "--system" ]; then
        shift
    fi

    local sub="${1:-}"
    shift || true

    local svc="${1:-}"
    local svc_clean
    svc_clean="$(__g2b_svc_name "$svc")"

    local brew_services
    brew_services="$(__g2b_brew_services_prefix)"

    case "$sub" in
        start)
            __g2b_308 "systemctl start $svc" "$brew_services start $svc_clean" __g2b_brew_services_run start "$svc_clean"
        ;;
        stop)
            __g2b_308 "systemctl stop $svc" "$brew_services stop $svc_clean" __g2b_brew_services_run stop "$svc_clean"
        ;;
        restart | reload)
            __g2b_308 "systemctl $sub $svc" "$brew_services restart $svc_clean" __g2b_brew_services_run restart "$svc_clean"
        ;;
        status)
            __g2b_308 "systemctl status $svc" "$brew_services list | grep $svc_clean" __g2b_brew_services_status "$svc_clean"
        ;;
        enable)
            __g2b_301 "systemctl enable $svc" "$brew_services start $svc_clean"
            printf 'Note: systemctl enable only enables startup. brew services start starts and registers the service.\n' >&2
            printf 'Run manually if intended: %s start %s\n' "$brew_services" "$svc_clean" >&2
        ;;
        disable)
            __g2b_301 "systemctl disable $svc" "$brew_services stop $svc_clean"
            printf 'Note: systemctl disable only disables startup. brew services stop stops and unregisters the service.\n' >&2
            printf 'Run manually if intended: %s stop %s\n' "$brew_services" "$svc_clean" >&2
        ;;
        is-active)
            __g2b_308 "systemctl is-active $svc" "$brew_services list | grep $svc_clean | grep started" __g2b_brew_services_is_active "$svc_clean"
        ;;
        list-units | list-unit-files)
            __g2b_308 "systemctl $sub" "$brew_services list" __g2b_brew_services_run list
        ;;
        daemon-reload)
            __g2b_301 "systemctl daemon-reload" "brew services restart <service>"
            printf 'launchd does not use systemd unit reload semantics. Restart the specific brew service if needed.\n' >&2
        ;;
        cat | edit)
            __g2b_301 "systemctl $sub $svc" "$brew_services info $svc_clean"
            printf 'Run manually if intended: %s info %s\n' "$brew_services" "$svc_clean" >&2
        ;;
        *)
            __g2b_301 "systemctl $sub $*" "brew services {start|stop|restart|list|info}"
        ;;
    esac
}

__g2b_service() {
    __g2b_brew_or_die || return $?

    local svc="${1:-}"
    local sub="${2:-}"
    local svc_clean
    svc_clean="$(__g2b_svc_name "$svc")"

    local brew_services
    brew_services="$(__g2b_brew_services_prefix)"

    if [ -z "$svc" ]; then
        __g2b_308 "service" "$brew_services list" __g2b_brew_services_run list
        return
    fi

    case "$sub" in
        start)
            __g2b_308 "service $svc start" "$brew_services start $svc_clean" __g2b_brew_services_run start "$svc_clean"
        ;;
        stop)
            __g2b_308 "service $svc stop" "$brew_services stop $svc_clean" __g2b_brew_services_run stop "$svc_clean"
        ;;
        restart)
            __g2b_308 "service $svc restart" "$brew_services restart $svc_clean" __g2b_brew_services_run restart "$svc_clean"
        ;;
        status)
            __g2b_308 "service $svc status" "$brew_services list | grep $svc_clean" __g2b_brew_services_status "$svc_clean"
        ;;
        *)
            __g2b_301 "service $*" "brew services {start|stop|restart|list|info}"
        ;;
    esac
}

# ------------------------------------------------------------------------------
# 5. Logs, tracing, dynamic linking
# ------------------------------------------------------------------------------

__g2b_journalctl() {
    local args="$*"

    if [[ "$args" == *"-f"* ]]; then
        __g2b_308 "journalctl $args" "log stream --style compact" log stream --style compact
        elif [[ "$args" == *"-b"* ]]; then
        __g2b_308 "journalctl -b" "log show --last boot --style compact" log show --last boot --style compact
        elif [ "${1:-}" = "-u" ] && [ -n "${2:-}" ]; then
        local unit
        unit="$(__g2b_svc_name "$2")"
        __g2b_301 "journalctl -u $2" "log show --predicate 'process CONTAINS \"$unit\"' --last 1h"
        printf 'macOS logs are not organized by systemd units. Run manually if intended:\n' >&2
        printf '  log show --predicate '\''process CONTAINS "%s"'\'' --last 1h --style compact\n' "$unit" >&2
        elif [[ "$args" == *"-xe"* ]]; then
        __g2b_301 "journalctl -xe" "log show --last 30m --style compact"
    else
        __g2b_301 "journalctl $args" "log show --last 15m --style compact"
    fi
}

__g2b_dmesg() {
    if [[ "$*" == *"-w"* ]] || [[ "$*" == *"--follow"* ]]; then
        __g2b_308 "dmesg $*" "log stream --predicate 'processID == 0' --style compact" log stream --predicate 'processID == 0' --style compact
    else
        __g2b_301 "dmesg $*" "sudo log show --predicate 'processID == 0' --last 15m"
        printf 'Run manually if intended: sudo log show --predicate '\''processID == 0'\'' --last 15m --style compact\n' >&2
    fi
}

__g2b_strace() {
    __g2b_301 "strace $*" "sudo dtruss $*"
    printf 'Run manually if intended: sudo dtruss %s\n' "$*" >&2
}

__g2b_ltrace() {
    __g2b_301 "ltrace $*" "dtruss / dtrace"
    printf 'macOS does not provide a safe 1:1 ltrace equivalent.\n' >&2
}

__g2b_ldd() {
    if [ "$#" -eq 0 ]; then
        __g2b_301 "ldd" "otool -L <binary>"
        return 64
    fi

    __g2b_308 "ldd $*" "otool -L $*" otool -L "$@"
}

# ------------------------------------------------------------------------------
# 6. /proc, /sys, and Linux file habits
# ------------------------------------------------------------------------------

__g2b_cat() {
    if [ "$#" -eq 1 ]; then
        case "$1" in
            /proc/cpuinfo)
                __g2b_redirect_msg 308 "cat /proc/cpuinfo" "sysctl -a | grep machdep.cpu"
                sysctl -a | grep machdep.cpu
                return 0
            ;;
            /proc/meminfo)
                __g2b_redirect_msg 308 "cat /proc/meminfo" "vm_stat && sysctl hw.memsize"
                vm_stat
                sysctl hw.memsize
                return 0
            ;;
            /proc/version)
                __g2b_308 "cat /proc/version" "uname -a" uname -a
                return 0
            ;;
            /proc/uptime)
                __g2b_308 "cat /proc/uptime" "sysctl -n kern.boottime" sysctl -n kern.boottime
                return 0
            ;;
            /proc/loadavg)
                __g2b_308 "cat /proc/loadavg" "sysctl -n vm.loadavg" sysctl -n vm.loadavg
                return 0
            ;;
            /proc/mounts)
                __g2b_308 "cat /proc/mounts" "mount" mount
                return 0
            ;;
            /proc/partitions)
                __g2b_308 "cat /proc/partitions" "diskutil list" diskutil list
                return 0
            ;;
            /etc/os-release)
                __g2b_redirect_msg 308 "cat /etc/os-release" "sw_vers"
                printf 'NAME="macOS"\n'
                printf 'VERSION="%s"\n' "$(sw_vers -productVersion)"
                printf 'ID=macos\n'
                printf 'PRETTY_NAME="macOS %s"\n' "$(sw_vers -productVersion)"
                return 0
            ;;
        esac
    fi

    command cat "$@"
}

__g2b_free() {
    __g2b_redirect_msg 308 "free $*" "vm_stat && sysctl hw.memsize"
    printf 'Total memory:\n'
    sysctl hw.memsize
    printf '\nVM stats:\n'
    vm_stat
    printf '\nTop summary:\n'
    top -l 1 -s 0 | grep PhysMem
}

# ------------------------------------------------------------------------------
# 7. Hardware and diagnostics
# ------------------------------------------------------------------------------

__g2b_lsblk() {
    __g2b_308 "lsblk $*" "diskutil list" diskutil list
}

__g2b_blkid() {
    __g2b_301 "blkid $*" "diskutil info -all"
    printf 'blkid and diskutil info do not have identical output formats.\n' >&2
    printf 'Run manually if intended: diskutil info -all\n' >&2
}

__g2b_fdisk() {
    if [ "${1:-}" = "-l" ] || [ "${1:-}" = "--list" ]; then
        __g2b_308 "fdisk $*" "diskutil list" diskutil list
    else
        command fdisk "$@"
    fi
}

__g2b_lsusb() {
    __g2b_308 "lsusb $*" "system_profiler SPUSBDataType" system_profiler SPUSBDataType
}

__g2b_lspci() {
    __g2b_308 "lspci $*" "system_profiler SPPCIDataType" system_profiler SPPCIDataType
}

__g2b_lsnvme() {
    __g2b_308 "lsnvme $*" "system_profiler SPNVMeDataType" system_profiler SPNVMeDataType
}

__g2b_lscpu() {
    __g2b_redirect_msg 308 "lscpu $*" "sysctl -a | grep machdep.cpu"
    sysctl -a | grep machdep.cpu
}

__g2b_lshw() {
    __g2b_308 "lshw $*" "system_profiler SPHardwareDataType" system_profiler SPHardwareDataType
}

__g2b_lsmem() {
    __g2b_308 "lsmem $*" "system_profiler SPMemoryDataType" system_profiler SPMemoryDataType
}

__g2b_dmidecode() {
    __g2b_301 "dmidecode $*" "system_profiler SPHardwareDataType"
    printf 'Run manually if intended: system_profiler SPHardwareDataType\n' >&2
}

__g2b_inxi() {
    __g2b_301 "inxi $*" "system_profiler SPHardwareDataType SPSoftwareDataType SPDisplaysDataType"
    printf 'Run manually if intended: system_profiler SPHardwareDataType SPSoftwareDataType SPDisplaysDataType\n' >&2
}

__g2b_acpi() {
    __g2b_308 "acpi $*" "pmset -g batt" pmset -g batt
}

__g2b_upower() {
    __g2b_301 "upower $*" "pmset -g batt"
    printf 'Run manually if intended: pmset -g batt\n' >&2
}

__g2b_sensors() {
    __g2b_301 "sensors $*" "sudo powermetrics --samplers smc -n 1"
    printf 'Run manually if intended: sudo powermetrics --samplers smc -n 1\n' >&2
}

__g2b_lswifi() {
    __g2b_308 "lswifi" "system_profiler SPAirPortDataType" system_profiler SPAirPortDataType
}

__g2b_lsnet() {
    __g2b_308 "lsnet" "system_profiler SPNetworkDataType" system_profiler SPNetworkDataType
}

__g2b_lsdisplay() {
    __g2b_308 "lsdisplay" "system_profiler SPDisplaysDataType" system_profiler SPDisplaysDataType
}

__g2b_xrandr() {
    __g2b_301 "xrandr $*" "system_profiler SPDisplaysDataType"
    printf 'macOS display control is not safely 1:1 compatible with xrandr.\n' >&2
    printf 'Run manually if intended: system_profiler SPDisplaysDataType\n' >&2
}

# ------------------------------------------------------------------------------
# 8. Networking muscle memory
# ------------------------------------------------------------------------------

__g2b_ip() {
    local brew_ip=""

    if [ -n "${HOMEBREW_PREFIX:-}" ] && [ -x "$HOMEBREW_PREFIX/bin/ip" ]; then
        brew_ip="$HOMEBREW_PREFIX/bin/ip"
        elif command -v ip >/dev/null 2>&1; then
        brew_ip="$(command -v ip)"
    fi

    if [ -n "$brew_ip" ]; then
        __g2b_308 "ip $*" "$brew_ip $*" "$brew_ip" "$@"
        return
    fi

    case "${1:-}" in
        a | addr | address)
            __g2b_308 "ip $*" "ifconfig" ifconfig
        ;;
        link)
            __g2b_308 "ip link" "ifconfig" ifconfig
        ;;
        route | r)
            __g2b_308 "ip route" "netstat -rn" netstat -rn
        ;;
        neigh | neighbor)
            __g2b_308 "ip neigh" "arp -a" arp -a
        ;;
        *)
            __g2b_301 "ip $*" "ifconfig / netstat -rn / arp -a"
            printf 'Install iproute2mac for better ip-command compatibility: brew install iproute2mac\n' >&2
        ;;
    esac
}

__g2b_ss() {
    local args="$*"

    if [[ "$args" == *"-tulpn"* ]] || [[ "$args" == *"-plnt"* ]] || [[ "$args" == *"-ltnp"* ]]; then
        __g2b_308 "ss $args" "sudo lsof -iTCP -sTCP:LISTEN -P -n" command sudo lsof -iTCP -sTCP:LISTEN -P -n
        elif [[ "$args" == *"-tunap"* ]] || [[ "$args" == *"-tuna"* ]]; then
        __g2b_308 "ss $args" "sudo lsof -i -P -n" command sudo lsof -i -P -n
    else
        __g2b_301 "ss $args" "netstat -anv"
        printf 'Run manually if intended: netstat -anv\n' >&2
    fi
}

__g2b_iwconfig() {
    __g2b_301 "iwconfig $*" "networksetup -listallhardwareports && system_profiler SPAirPortDataType"
}

__g2b_iw() {
    __g2b_301 "iw $*" "system_profiler SPAirPortDataType"
}

__g2b_nmcli() {
    __g2b_301 "nmcli $*" "networksetup"
    printf 'macOS does not use NetworkManager. Try: networksetup -listallhardwareports\n' >&2
}

__g2b_resolvectl() {
    __g2b_301 "resolvectl $*" "scutil --dns"
    printf 'Run manually if intended: scutil --dns\n' >&2
}

__g2b_systemd_resolve() {
    __g2b_resolvectl "$@"
}

__g2b_digflush() {
    __g2b_308 "systemd-resolve --flush-caches" "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder" sh -c 'sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
}

__g2b_netplan() {
    __g2b_301 "netplan $*" "networksetup / System Settings > Network"
    printf 'macOS does not use netplan. Try: networksetup -listallhardwareports\n' >&2
}

__g2b_ifup() {
    __g2b_301 "ifup $*" "networksetup -setnetworkserviceenabled <service> on"
}

__g2b_ifdown() {
    __g2b_301 "ifdown $*" "networksetup -setnetworkserviceenabled <service> off"
}

# ------------------------------------------------------------------------------
# 9. Firewall redirects
# ------------------------------------------------------------------------------

__g2b_ufw() {
    local sub="${1:-}"
    shift || true

    case "$sub" in
        status)
            __g2b_301 "ufw status" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate"
        ;;
        enable)
            __g2b_301 "ufw enable" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
        ;;
        disable)
            __g2b_301 "ufw disable" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off"
        ;;
        app)
            __g2b_301 "ufw app $*" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps"
        ;;
        *)
            __g2b_301 "ufw $sub $*" "socketfilterfw / pfctl"
        ;;
    esac
}

__g2b_iptables() {
    if [ "${1:-}" = "-L" ] || [ "${1:-}" = "--list" ]; then
        __g2b_301 "iptables $*" "sudo pfctl -sr"
    else
        __g2b_301 "iptables $*" "pfctl"
    fi

    printf 'Not auto-executing because iptables and pf rules are not safely 1:1 compatible.\n' >&2
}

__g2b_nft() {
    __g2b_301 "nft $*" "pfctl"
    printf 'Not auto-executing because nftables and pf rules are not safely 1:1 compatible.\n' >&2
}

__g2b_firewall_cmd() {
    __g2b_301 "firewall-cmd $*" "socketfilterfw / pfctl"
}

# ------------------------------------------------------------------------------
# 10. Desktop/Linux GUI helpers
# ------------------------------------------------------------------------------

__g2b_xdg_open() {
    __g2b_308 "xdg-open $*" "open $*" open "$@"
}

__g2b_sensible_browser() {
    __g2b_308 "sensible-browser $*" "open $*" open "$@"
}

__g2b_gio() {
    if [ "${1:-}" = "open" ]; then
        shift
        __g2b_308 "gio open $*" "open $*" open "$@"
    else
        __g2b_301 "gio $*" "open"
    fi
}

__g2b_nautilus() {
    __g2b_301 "nautilus $*" "open ${*:-.}"
    printf 'Run manually if intended: open %s\n' "${*:-.}" >&2
}

__g2b_dolphin() {
    __g2b_301 "dolphin $*" "open ${*:-.}"
    printf 'Run manually if intended: open %s\n' "${*:-.}" >&2
}

__g2b_thunar() {
    __g2b_301 "thunar $*" "open ${*:-.}"
    printf 'Run manually if intended: open %s\n' "${*:-.}" >&2
}

__g2b_notify_send() {
    local title="${1:-Notification}"
    shift || true
    local body="$*"

    __g2b_301 "notify-send $title $body" "osascript display notification"
    printf 'Run manually if intended:\n' >&2
    printf '  osascript -e '\''display notification "%s" with title "%s"'\''\n' "$body" "$title" >&2
}

__g2b_xclip() {
    if [[ "$*" == *"-o"* ]]; then
        __g2b_308 "xclip $*" "pbpaste" pbpaste
    else
        __g2b_308 "xclip $*" "pbcopy" pbcopy
    fi
}

__g2b_xsel() {
    if [[ "$*" == *"-o"* ]]; then
        __g2b_308 "xsel $*" "pbpaste" pbpaste
    else
        __g2b_308 "xsel $*" "pbcopy" pbcopy
    fi
}

__g2b_wl_copy() {
    __g2b_308 "wl-copy" "pbcopy" pbcopy
}

__g2b_wl_paste() {
    __g2b_308 "wl-paste" "pbpaste" pbpaste
}

# ------------------------------------------------------------------------------
# 11. Kernel module / bootloader commands
# ------------------------------------------------------------------------------

__g2b_lsmod() {
    __g2b_301 "lsmod" "kmutil showloaded"
    printf 'Run manually if intended: kmutil showloaded\n' >&2
}

__g2b_modprobe() {
    __g2b_301 "modprobe $*" "kmutil / kextload"
    printf 'Not auto-loading kernel extensions because Linux modules and macOS kexts are not safely 1:1 compatible.\n' >&2
}

__g2b_insmod() {
    __g2b_301 "insmod $*" "kmutil / kextload"
    printf 'Not auto-loading kernel extensions because Linux modules and macOS kexts are not safely 1:1 compatible.\n' >&2
}

__g2b_rmmod() {
    __g2b_301 "rmmod $*" "kmutil / kextunload"
    printf 'Not auto-unloading kernel extensions because Linux modules and macOS kexts are not safely 1:1 compatible.\n' >&2
}

__g2b_update_grub() {
    __g2b_301 "update-grub" "not applicable on normal macOS boot"
    printf 'macOS does not use GRUB for normal boot management.\n' >&2
}

__g2b_grub_install() {
    __g2b_301 "grub-install $*" "not applicable on normal macOS boot"
    printf 'macOS does not use GRUB for normal boot management.\n' >&2
}

__g2b_update_initramfs() {
    __g2b_301 "update-initramfs $*" "not applicable on macOS"
}

__g2b_mkinitcpio() {
    __g2b_301 "mkinitcpio $*" "not applicable on macOS"
}

__g2b_dracut() {
    __g2b_301 "dracut $*" "not applicable on macOS"
}

# ------------------------------------------------------------------------------
# 12. Power commands
# ------------------------------------------------------------------------------

__g2b_reboot() {
    __g2b_301 "reboot" "sudo shutdown -r now"
    printf 'Run manually if intended: sudo shutdown -r now\n' >&2
}

__g2b_poweroff() {
    __g2b_301 "poweroff" "sudo shutdown -h now"
    printf 'Run manually if intended: sudo shutdown -h now\n' >&2
}

__g2b_halt() {
    __g2b_301 "halt" "sudo shutdown -h now"
    printf 'Run manually if intended: sudo shutdown -h now\n' >&2
}

__g2b_init() {
    case "${1:-}" in
        0)
            __g2b_301 "init 0" "sudo shutdown -h now"
            printf 'Run manually if intended: sudo shutdown -h now\n' >&2
        ;;
        6)
            __g2b_301 "init 6" "sudo shutdown -r now"
            printf 'Run manually if intended: sudo shutdown -r now\n' >&2
        ;;
        *)
            __g2b_301 "init $*" "launchd has no SysV runlevels"
        ;;
    esac
}

# ------------------------------------------------------------------------------
# 13. Host / time / system info
# ------------------------------------------------------------------------------

__g2b_hostnamectl() {
    __g2b_redirect_msg 308 "hostnamectl $*" "scutil / sw_vers / uname"

    printf 'Static hostname: %s\n' "$(scutil --get ComputerName 2>/dev/null)"
    printf 'Operating System: macOS %s\n' "$(sw_vers -productVersion)"
    printf 'Kernel: Darwin %s\n' "$(uname -r)"
    printf 'Architecture: %s\n' "$(uname -m)"
}

__g2b_timedatectl() {
    __g2b_redirect_msg 308 "timedatectl $*" "systemsetup -gettimezone / date"

    printf 'Local time: %s\n' "$(date)"
    printf 'Time zone: '
    systemsetup -gettimezone 2>/dev/null | sed 's/Time Zone: //'
}

__g2b_localectl() {
    __g2b_301 "localectl $*" "defaults read -g AppleLocale"
    printf 'Run manually if intended: defaults read -g AppleLocale\n' >&2
}

__g2b_loginctl() {
    __g2b_301 "loginctl $*" "launchctl / who"
    printf 'macOS launchd/login sessions do not map cleanly to systemd-logind.\n' >&2
}

__g2b_nproc() {
    __g2b_308 "nproc" "sysctl -n hw.ncpu" sysctl -n hw.ncpu
}

__g2b_pidof() {
    __g2b_308 "pidof $*" "pgrep -x $*" pgrep -x "$@"
}

# ------------------------------------------------------------------------------
# 14. user/group commands: teach only
# ------------------------------------------------------------------------------

__g2b_useradd() {
    __g2b_301 "useradd $*" "sysadminctl -addUser / dscl"
    printf 'Not auto-executing. macOS user creation needs different required fields.\n' >&2
    printf 'Example: sudo sysadminctl -addUser USERNAME -fullName "Full Name" -password -\n' >&2
}

__g2b_adduser() {
    __g2b_useradd "$@"
}

__g2b_usermod() {
    __g2b_301 "usermod $*" "dscl"
    printf 'Not auto-executing. Linux usermod flags do not map safely to macOS dscl.\n' >&2
}

__g2b_userdel() {
    __g2b_301 "userdel $*" "sysadminctl -deleteUser / dscl"
    printf 'Not auto-executing user deletion.\n' >&2
}

__g2b_groupadd() {
    __g2b_301 "groupadd $*" "dscl . -create /Groups/GROUP"
    printf 'Not auto-executing group creation.\n' >&2
}

__g2b_groupdel() {
    __g2b_301 "groupdel $*" "dscl . -delete /Groups/GROUP"
    printf 'Not auto-executing group deletion.\n' >&2
}

# ------------------------------------------------------------------------------
# 15. SELinux/AppArmor-ish concepts
# ------------------------------------------------------------------------------

__g2b_getenforce() {
    __g2b_301 "getenforce" "csrutil status"
    printf 'SELinux is not used by macOS. SIP is the closest security-mode concept.\n' >&2
    printf 'Run manually if intended: csrutil status\n' >&2
}

__g2b_setenforce() {
    __g2b_301 "setenforce $*" "csrutil enable/disable from Recovery"
    printf 'Not auto-executing. SIP changes require macOS Recovery.\n' >&2
}

__g2b_aa_status() {
    __g2b_301 "aa-status" "not applicable; macOS does not use AppArmor"
}

# ------------------------------------------------------------------------------
# 16. Pass-through proxies: cat, sudo
# ------------------------------------------------------------------------------

cat() {
    __g2b_cat "$@"
}

sudo() {
    local cmd="${1:-}"

    case "$cmd" in
        apt | apt-get)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_apt "$@"
        ;;
        apt-cache)
            shift
            __g2b_note "dropping sudo"
            __g2b_apt_cache "$@"
        ;;
        pacman)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_pacman "$@"
        ;;
        dnf | yum)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_dnf "$@"
        ;;
        zypper)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_zypper "$@"
        ;;
        apk)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_apk "$@"
        ;;
        xbps-install)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_xbps_install "$@"
        ;;
        xbps-remove)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_xbps_remove "$@"
        ;;
        emerge)
            shift
            __g2b_note "dropping sudo because Homebrew should not run as root"
            __g2b_emerge "$@"
        ;;
        snap)
            shift
            __g2b_note "dropping sudo"
            __g2b_snap "$@"
        ;;
        flatpak)
            shift
            __g2b_note "dropping sudo"
            __g2b_flatpak "$@"
        ;;
        systemctl | systemd)
            shift
            GNU2BSD_SUDO=1 __g2b_systemctl "$@"
        ;;
        service)
            shift
            GNU2BSD_SUDO=1 __g2b_service "$@"
        ;;
        *)
            command sudo "$@"
        ;;
    esac
}

# ------------------------------------------------------------------------------
# 17. Fat-finger command-not-found redirects
# ------------------------------------------------------------------------------

__g2b_typo() {
    local cmd="$1"
    shift || true

    case "$cmd" in
        aptt | aptget | apt-gte | apt-gat)
            __g2b_redirect_msg 308 "$cmd $*" "apt $*"
            __g2b_apt "$@"
        ;;
        pacamn | packman | pacmn | pacmam)
            __g2b_redirect_msg 308 "$cmd $*" "pacman $*"
            __g2b_pacman "$@"
        ;;
        dnf5 | dnff | ymu | yumm)
            __g2b_redirect_msg 308 "$cmd $*" "dnf $*"
            __g2b_dnf "$@"
        ;;
        zyppr | zyper | zyppe)
            __g2b_redirect_msg 308 "$cmd $*" "zypper $*"
            __g2b_zypper "$@"
        ;;
        systemclt | systmctl | sytemctl | systemct | systemctrl | sysctlctl)
            __g2b_redirect_msg 308 "$cmd $*" "systemctl $*"
            __g2b_systemctl "$@"
        ;;
        journalclt | journactl | journalct | jounalctl)
            __g2b_redirect_msg 308 "$cmd $*" "journalctl $*"
            __g2b_journalctl "$@"
        ;;
        *)
            return 127
        ;;
    esac
}

if [ -n "${BASH_VERSION:-}" ]; then
    command_not_found_handle() {
        __g2b_typo "$@"
    }
    elif [ -n "${ZSH_VERSION:-}" ]; then
    command_not_found_handler() {
        __g2b_typo "$@"
    }
fi

# ------------------------------------------------------------------------------
# 18. Apply mappings
# Most commands map only if missing.
# cat/sudo are intentional pass-through functions.
# fdisk/dmesg/ldd are force-wrapped because macOS/native behavior differs enough.
# ------------------------------------------------------------------------------

__g2b_map_if_missing apt __g2b_apt
__g2b_map_if_missing apt-get __g2b_apt
__g2b_map_if_missing apt-cache __g2b_apt_cache
__g2b_map_if_missing add-apt-repository __g2b_add_apt_repository

__g2b_map_if_missing pacman __g2b_pacman
__g2b_map_if_missing yay __g2b_yay
__g2b_map_if_missing paru __g2b_paru
__g2b_map_if_missing dnf __g2b_dnf
__g2b_map_if_missing yum __g2b_dnf
__g2b_map_if_missing zypper __g2b_zypper
__g2b_map_if_missing apk __g2b_apk
__g2b_map_if_missing xbps-install __g2b_xbps_install
__g2b_map_if_missing xbps-remove __g2b_xbps_remove
__g2b_map_if_missing emerge __g2b_emerge
__g2b_map_if_missing snap __g2b_snap
__g2b_map_if_missing flatpak __g2b_flatpak

__g2b_map_if_missing systemctl __g2b_systemctl
__g2b_map_if_missing systemd __g2b_systemctl
__g2b_map_if_missing service __g2b_service

__g2b_map_if_missing journalctl __g2b_journalctl
__g2b_map_if_missing strace __g2b_strace
__g2b_map_if_missing ltrace __g2b_ltrace

__g2b_map_if_missing free __g2b_free
__g2b_map_if_missing lsblk __g2b_lsblk
__g2b_map_if_missing blkid __g2b_blkid
__g2b_map_if_missing lsusb __g2b_lsusb
__g2b_map_if_missing lspci __g2b_lspci
__g2b_map_if_missing lsnvme __g2b_lsnvme
__g2b_map_if_missing lscpu __g2b_lscpu
__g2b_map_if_missing lshw __g2b_lshw
__g2b_map_if_missing lsmem __g2b_lsmem
__g2b_map_if_missing dmidecode __g2b_dmidecode
__g2b_map_if_missing inxi __g2b_inxi
__g2b_map_if_missing acpi __g2b_acpi
__g2b_map_if_missing upower __g2b_upower
__g2b_map_if_missing sensors __g2b_sensors
__g2b_map_if_missing lswifi __g2b_lswifi
__g2b_map_if_missing lsnet __g2b_lsnet
__g2b_map_if_missing lsdisplay __g2b_lsdisplay
__g2b_map_if_missing xrandr __g2b_xrandr

__g2b_map_if_missing ip __g2b_ip
__g2b_map_if_missing ss __g2b_ss
__g2b_map_if_missing iwconfig __g2b_iwconfig
__g2b_map_if_missing iw __g2b_iw
__g2b_map_if_missing nmcli __g2b_nmcli
__g2b_map_if_missing resolvectl __g2b_resolvectl
__g2b_map_if_missing systemd-resolve __g2b_systemd_resolve
__g2b_map_if_missing digflush __g2b_digflush
__g2b_map_if_missing netplan __g2b_netplan
__g2b_map_if_missing ifup __g2b_ifup
__g2b_map_if_missing ifdown __g2b_ifdown

__g2b_map_if_missing ufw __g2b_ufw
__g2b_map_if_missing iptables __g2b_iptables
__g2b_map_if_missing nft __g2b_nft
__g2b_map_if_missing firewall-cmd __g2b_firewall_cmd

__g2b_map_if_missing xdg-open __g2b_xdg_open
__g2b_map_if_missing sensible-browser __g2b_sensible_browser
__g2b_map_if_missing gio __g2b_gio
__g2b_map_if_missing nautilus __g2b_nautilus
__g2b_map_if_missing dolphin __g2b_dolphin
__g2b_map_if_missing thunar __g2b_thunar
__g2b_map_if_missing notify-send __g2b_notify_send
__g2b_map_if_missing xclip __g2b_xclip
__g2b_map_if_missing xsel __g2b_xsel
__g2b_map_if_missing wl-copy __g2b_wl_copy
__g2b_map_if_missing wl-paste __g2b_wl_paste

__g2b_map_if_missing lsmod __g2b_lsmod
__g2b_map_if_missing modprobe __g2b_modprobe
__g2b_map_if_missing insmod __g2b_insmod
__g2b_map_if_missing rmmod __g2b_rmmod
__g2b_map_if_missing update-grub __g2b_update_grub
__g2b_map_if_missing grub-install __g2b_grub_install
__g2b_map_if_missing update-initramfs __g2b_update_initramfs
__g2b_map_if_missing mkinitcpio __g2b_mkinitcpio
__g2b_map_if_missing dracut __g2b_dracut

__g2b_map_if_missing poweroff __g2b_poweroff
__g2b_map_if_missing init __g2b_init

__g2b_map_if_missing hostnamectl __g2b_hostnamectl
__g2b_map_if_missing timedatectl __g2b_timedatectl
__g2b_map_if_missing localectl __g2b_localectl
__g2b_map_if_missing loginctl __g2b_loginctl
__g2b_map_if_missing nproc __g2b_nproc
__g2b_map_if_missing pidof __g2b_pidof

__g2b_map_if_missing useradd __g2b_useradd
__g2b_map_if_missing adduser __g2b_adduser
__g2b_map_if_missing usermod __g2b_usermod
__g2b_map_if_missing userdel __g2b_userdel
__g2b_map_if_missing groupadd __g2b_groupadd
__g2b_map_if_missing groupdel __g2b_groupdel

__g2b_map_if_missing getenforce __g2b_getenforce
__g2b_map_if_missing setenforce __g2b_setenforce
__g2b_map_if_missing aa-status __g2b_aa_status

alias fdisk='__g2b_fdisk'
alias dmesg='__g2b_dmesg'
alias ldd='__g2b_ldd'

# ------------------------------------------------------------------------------
# 19. Help
# ------------------------------------------------------------------------------

gnu2bsd-help() {
	cat <<'HELP'
gnu2bsd examples:

308 = close-enough redirect, then execute:
  apt install wget              -> brew install wget
  sudo apt update               -> apt update, root dropped
  pacman -Syu                   -> brew update && brew upgrade
  dnf install htop              -> brew install htop
  zypper in jq                  -> brew install jq
  apk add curl                  -> brew install curl

  systemctl start nginx         -> brew services start nginx
  sudo systemctl start nginx    -> sudo brew services start nginx
  service nginx restart         -> brew services restart nginx
  journalctl -f                 -> log stream --style compact
  journalctl -b                 -> log show --last boot

  lsblk                         -> diskutil list
  lsusb                         -> system_profiler SPUSBDataType
  lspci                         -> system_profiler SPPCIDataType
  lscpu                         -> sysctl -a | grep machdep.cpu
  free -h                       -> vm_stat + memory summary
  cat /proc/cpuinfo             -> sysctl CPU info
  cat /etc/os-release           -> sw_vers-style macOS info

  ip addr                       -> iproute2mac ip OR ifconfig fallback
  ss -tulpn                     -> sudo lsof -iTCP -sTCP:LISTEN -P -n
  xdg-open file                 -> open file
  xclip / xsel                  -> pbcopy / pbpaste
  ldd binary                    -> otool -L binary

301 = conceptual redirect, teach only, do not execute:
  iptables                      -> pfctl
  nft                           -> pfctl
  ufw                           -> socketfilterfw / pfctl
  snap                          -> brew casks/formulas
  flatpak                       -> brew casks
  modprobe                      -> kmutil / kextload
  useradd/usermod/userdel       -> sysadminctl / dscl
  setenforce/getenforce         -> csrutil / SIP
HELP
}
# <<< linuxify <<<
GNUBLOCK
	ok "Added Linuxify GNU-tools block to ~/.zprofile"
else
	ok "Linuxify GNU-tools block already in ~/.zprofile"
fi

mkdir -p "$FISH_DIR"
touch "$FISH_CONFIG"

if ! grep -q "linuxify" "$FISH_CONFIG" 2>/dev/null; then
	cat <<'FISHBLOCK' >>"$FISH_CONFIG"
# >>> linuxify >>>
if status is-interactive
    # ==============================================================================
    # GNU-to-BSD / Linux-to-macOS Compatibility Layer for macOS
    #
    # Rule:
    #   308 = close-enough / safe redirect, then execute
    #   301 = conceptual / approximate / risky redirect, explain only
    # ==============================================================================

    if test (uname -s 2>/dev/null) != Darwin
        return
    end

    # ------------------------------------------------------------------------------
    # 0. Core helpers
    # ------------------------------------------------------------------------------

    function __g2b_have
        type -q -- $argv[1]
    end

    function __g2b_brew_bin
        if set -q HOMEBREW_PREFIX; and test -x "$HOMEBREW_PREFIX/bin/brew"
            printf '%s\n' "$HOMEBREW_PREFIX/bin/brew"
        else if test -x /opt/homebrew/bin/brew
            printf '%s\n' /opt/homebrew/bin/brew
        else if test -x /usr/local/bin/brew
            printf '%s\n' /usr/local/bin/brew
        else if command -sq brew
            command -s brew
        else
            return 1
        end
    end

    function __g2b_brew
        set -l b (__g2b_brew_bin); or return 127
        $b $argv
    end

    function __g2b_brew_or_die
        __g2b_brew_bin >/dev/null 2>&1
        and return 0

        printf '\033[1;31mgnu2bsd target missing:\033[0m Homebrew is not installed or not in PATH.\n' >&2
        printf 'Install Homebrew first, then retry.\n' >&2
        return 127
    end

    function __g2b_redirect_msg
        set -l code $argv[1]
        set -l old $argv[2]
        set -l new $argv[3]

        switch "$code"
            case 308
                printf '\033[1;32m308 Permanent Redirect\033[0m: command "%s" permanently moved to "%s"\n' "$old" "$new" >&2
                printf '\033[1;36mredirecting to:\033[0m %s\n' "$new" >&2
            case 301
                printf '\033[1;33m301 Moved Permanently\033[0m: command "%s" permanently moved to "%s"\n' "$old" "$new" >&2
                printf '\033[1;31mnot auto-executing:\033[0m mapping is conceptual, approximate, or not safely 1:1 compatible\n' >&2
                printf '\033[1;36mBSD/macOS equivalent:\033[0m %s\n' "$new" >&2
            case '*'
                printf '\033[1;33m%s Redirect\033[0m: command "%s" moved to "%s"\n' "$code" "$old" "$new" >&2
        end
    end

    function __g2b_301
        __g2b_redirect_msg 301 "$argv[1]" "$argv[2]"
    end

    function __g2b_308
        set -l old "$argv[1]"
        set -l new "$argv[2]"
        set -l run $argv[3..-1]

        __g2b_redirect_msg 308 "$old" "$new"
        $run
    end

    function __g2b_note
        printf '\033[1;36mgnu2bsd:\033[0m %s\n' "$argv" >&2
    end

    function __g2b_pkg_clean
        set -g __G2B_PKG_ARGS

        for a in $argv
            switch "$a"
                case -y --yes --assume-yes --noconfirm --needed --no-install-recommends --best --allowerasing --skip-broken --refresh
                case --
                case '*'
                    set -g __G2B_PKG_ARGS $__G2B_PKG_ARGS "$a"
            end
        end
    end

    function __g2b_svc_name
        set -l s "$argv[1]"
        set s (string replace -r '\.service$' '' -- "$s")
        printf '%s' "$s"
    end

    function __g2b_map_if_missing
        set -l cmd "$argv[1]"
        set -l target "$argv[2]"

        type -q -- "$cmd"
        and return 0

        functions -c "$target" "$cmd" 2>/dev/null
    end

    function __g2b_join
        string join ' ' -- $argv
    end

    # ------------------------------------------------------------------------------
    # 1. Homebrew + GNU path/man/info/build-env injection
    # ------------------------------------------------------------------------------

    function __g2b_colon_prepend
        set -l var "$argv[1]"
        set -l dir "$argv[2]"

        test -n "$var"; or return 0
        test -n "$dir"; or return 0
        test -d "$dir"; or return 0

        switch "$var"
            case PATH
                contains -- "$dir" $PATH; or set -gx PATH "$dir" $PATH
            case MANPATH
                contains -- "$dir" $MANPATH; or set -gx MANPATH "$dir" $MANPATH
            case INFOPATH
                contains -- "$dir" $INFOPATH; or set -gx INFOPATH "$dir" $INFOPATH
            case PKG_CONFIG_PATH
                contains -- "$dir" $PKG_CONFIG_PATH; or set -gx PKG_CONFIG_PATH "$dir" $PKG_CONFIG_PATH
        end
    end

    function __g2b_colon_prepend_keep_default
        set -l var "$argv[1]"
        set -l dir "$argv[2]"

        test -n "$var"; or return 0
        test -n "$dir"; or return 0
        test -d "$dir"; or return 0

        switch "$var"
            case MANPATH
                if contains -- "$dir" $MANPATH
                    return 0
                end

                if set -q MANPATH[1]
                    set -gx MANPATH "$dir" $MANPATH
                else
                    set -gx MANPATH "$dir" ""
                end
            case INFOPATH
                if contains -- "$dir" $INFOPATH
                    return 0
                end

                if set -q INFOPATH[1]
                    set -gx INFOPATH "$dir" $INFOPATH
                else
                    set -gx INFOPATH "$dir" ""
                end
            case '*'
                __g2b_colon_prepend "$var" "$dir"
        end
    end

    function __g2b_space_prepend
        set -l var "$argv[1]"
        set -l item "$argv[2]"

        test -n "$var"; or return 0
        test -n "$item"; or return 0

        switch "$var"
            case LDFLAGS
                contains -- "$item" $LDFLAGS; or set -gx LDFLAGS "$item" $LDFLAGS
            case CPPFLAGS
                contains -- "$item" $CPPFLAGS; or set -gx CPPFLAGS "$item" $CPPFLAGS
        end
    end

    function __g2b_add_gnubin_formula
        for formula in $argv
            set -l opt "$BREW_HOME/opt/$formula"
            __g2b_colon_prepend PATH "$opt/libexec/gnubin"
            __g2b_colon_prepend_keep_default MANPATH "$opt/libexec/gnuman"
        end
    end

    function __g2b_add_opt_bin_formula
        for formula in $argv
            set -l opt "$BREW_HOME/opt/$formula"
            __g2b_colon_prepend PATH "$opt/bin"
            __g2b_colon_prepend_keep_default MANPATH "$opt/share/man"
            __g2b_colon_prepend_keep_default INFOPATH "$opt/share/info"
        end
    end

    function __g2b_add_build_formula
        for formula in $argv
            set -l opt "$BREW_HOME/opt/$formula"

            __g2b_colon_prepend PATH "$opt/bin"
            __g2b_colon_prepend_keep_default MANPATH "$opt/share/man"
            __g2b_colon_prepend_keep_default INFOPATH "$opt/share/info"

            test -d "$opt/lib"; and __g2b_space_prepend LDFLAGS "-L$opt/lib"
            test -d "$opt/include"; and __g2b_space_prepend CPPFLAGS "-I$opt/include"
            test -d "$opt/lib/pkgconfig"; and __g2b_colon_prepend PKG_CONFIG_PATH "$opt/lib/pkgconfig"
        end
    end

    if not set -q HOMEBREW_PREFIX
        if test -x /opt/homebrew/bin/brew
            eval (/opt/homebrew/bin/brew shellenv)
        else if test -x /usr/local/bin/brew
            eval (/usr/local/bin/brew shellenv)
        end
    end

    set -g BREW_HOME ""

    if set -q HOMEBREW_PREFIX
        set BREW_HOME "$HOMEBREW_PREFIX"
    else if command -sq brew
        set BREW_HOME (brew --prefix 2>/dev/null)
    end

    if test -n "$BREW_HOME"; and test -d "$BREW_HOME"
        set -gx HOMEBREW_PREFIX "$BREW_HOME"

        __g2b_colon_prepend PATH "$BREW_HOME/bin"
        __g2b_colon_prepend PATH "$BREW_HOME/sbin"
        __g2b_colon_prepend_keep_default MANPATH "$BREW_HOME/share/man"
        __g2b_colon_prepend_keep_default INFOPATH "$BREW_HOME/share/info"

        __g2b_colon_prepend PATH "$HOME/.local/bin"

        __g2b_add_gnubin_formula \
            coreutils \
            make \
            ed \
            findutils \
            gnu-indent \
            gnu-sed \
            gnu-tar \
            gnu-which \
            grep \
            gawk \
            gnu-time \
            diffutils

        __g2b_add_opt_bin_formula \
            gnu-getopt \
            m4 \
            file-formula \
            unzip

        __g2b_add_build_formula \
            flex \
            bison \
            libressl \
            openssl@3 \
            readline \
            sqlite \
            gettext \
            zlib \
            xz
    end

    set -e BREW_HOME

    # ------------------------------------------------------------------------------
    # 2. Package management handlers
    # ------------------------------------------------------------------------------

    function __g2b_brew_update_upgrade
        __g2b_brew update
        and __g2b_brew upgrade
    end

    function __g2b_apt
        __g2b_brew_or_die; or return $status

        while test (count $argv) -gt 0
            switch "$argv[1]"
                case -y --yes --assume-yes
                    set -e argv[1]
                case '*'
                    break
            end
        end

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        switch "$sub"
            case install
                __g2b_pkg_clean $argv
                set -l s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "apt install $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
            case reinstall
                __g2b_pkg_clean $argv
                set -l s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "apt reinstall $s" "brew reinstall $s" __g2b_brew reinstall $__G2B_PKG_ARGS
            case remove
                __g2b_pkg_clean $argv
                set -l s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "apt remove $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
            case purge
                __g2b_pkg_clean $argv
                set -l s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "apt purge $s" "brew uninstall --zap $s" __g2b_brew uninstall --zap $__G2B_PKG_ARGS
            case update
                __g2b_308 "apt update" "brew update" __g2b_brew update
            case upgrade dist-upgrade full-upgrade
                __g2b_308 "apt $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
            case autoremove
                __g2b_308 "apt autoremove" "brew autoremove" __g2b_brew autoremove
            case autoclean clean
                __g2b_308 "apt $sub" "brew cleanup" __g2b_brew cleanup
            case search
                set -l s (__g2b_join $argv)
                __g2b_308 "apt search $s" "brew search $s" __g2b_brew search $argv
            case show info policy
                set -l s (__g2b_join $argv)
                __g2b_308 "apt $sub $s" "brew info $s" __g2b_brew info $argv
            case list
                set -l s (__g2b_join $argv)
                __g2b_308 "apt list $s" "brew list $s" __g2b_brew list $argv
            case edit-sources
                __g2b_301 "apt edit-sources" "brew tap / brew untap"
                printf 'Homebrew uses taps instead of apt source files.\n' >&2
                printf 'Examples:\n  brew tap owner/repo\n  brew untap owner/repo\n' >&2
            case '*'
                set -l s (__g2b_join $argv)
                __g2b_301 "apt $sub $s" "brew help"
                printf 'Run manually if intended: brew help\n' >&2
        end
    end

    function __g2b_apt_cache
        __g2b_brew_or_die; or return $status

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case search
                __g2b_308 "apt-cache search $s" "brew search $s" __g2b_brew search $argv
            case show showpkg policy
                __g2b_308 "apt-cache $sub $s" "brew info $s" __g2b_brew info $argv
            case '*'
                __g2b_301 "apt-cache $sub $s" "brew search / brew info"
        end
    end

    function __g2b_add_apt_repository
        __g2b_brew_or_die; or return $status
        set -l s (__g2b_join $argv)
        __g2b_301 "add-apt-repository $s" "brew tap $s"
        printf 'Homebrew taps are not always equivalent to apt repositories.\n' >&2
        printf 'Run manually if intended: brew tap %s\n' "$s" >&2
    end

    function __g2b_pacman
        __g2b_brew_or_die; or return $status

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case -S --sync
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "pacman -S $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
            case -Syu -Syyu -Syuu -Su
                __g2b_308 "pacman $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
            case -Sy
                __g2b_308 "pacman -Sy" "brew update" __g2b_brew update
            case -R -Rs -Rns
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "pacman $sub $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
            case -Ss
                __g2b_308 "pacman -Ss $s" "brew search $s" __g2b_brew search $argv
            case -Si -Qi
                __g2b_308 "pacman $sub $s" "brew info $s" __g2b_brew info $argv
            case -Q -Qe
                __g2b_308 "pacman $sub" "brew list" __g2b_brew list
            case -Qs
                __g2b_redirect_msg 308 "pacman -Qs $s" "brew list | grep $s"
                __g2b_brew list | grep "$s"; or true
            case -Ql
                __g2b_308 "pacman -Ql $s" "brew list --verbose $s" __g2b_brew list --verbose $argv
            case -Qdt
                __g2b_308 "pacman -Qdt" "brew autoremove" __g2b_brew autoremove
            case -Sc -Scc
                __g2b_308 "pacman $sub" "brew cleanup" __g2b_brew cleanup
            case '*'
                __g2b_301 "pacman $sub $s" "brew help"
                printf 'Run manually if intended: brew help\n' >&2
        end
    end

    function __g2b_yay
        __g2b_brew_or_die; or return $status
        set -l s (__g2b_join $argv)
        __g2b_308 "yay $s" "brew $s" __g2b_brew $argv
    end

    function __g2b_paru
        __g2b_brew_or_die; or return $status
        set -l s (__g2b_join $argv)
        __g2b_308 "paru $s" "brew $s" __g2b_brew $argv
    end

    function __g2b_dnf
        __g2b_brew_or_die; or return $status

        while test (count $argv) -gt 0
            switch "$argv[1]"
                case -y --assumeyes --best --allowerasing --skip-broken
                    set -e argv[1]
                case '*'
                    break
            end
        end

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case install
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "dnf install $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
            case reinstall
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "dnf reinstall $s" "brew reinstall $s" __g2b_brew reinstall $__G2B_PKG_ARGS
            case remove erase
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "dnf $sub $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
            case update upgrade
                __g2b_308 "dnf $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
            case check-update makecache
                __g2b_308 "dnf $sub" "brew update" __g2b_brew update
            case search
                __g2b_308 "dnf search $s" "brew search $s" __g2b_brew search $argv
            case info
                __g2b_308 "dnf info $s" "brew info $s" __g2b_brew info $argv
            case list
                __g2b_308 "dnf list $s" "brew list $s" __g2b_brew list $argv
            case autoremove
                __g2b_308 "dnf autoremove" "brew autoremove" __g2b_brew autoremove
            case clean
                __g2b_308 "dnf clean $s" "brew cleanup" __g2b_brew cleanup
            case groupinstall group
                __g2b_301 "dnf $sub $s" "brew bundle / Brewfile"
                printf 'Homebrew has no true dnf group equivalent. Use a Brewfile for grouped installs.\n' >&2
            case '*'
                __g2b_301 "dnf $sub $s" "brew help"
                printf 'Run manually if intended: brew help\n' >&2
        end
    end

    function __g2b_zypper
        __g2b_brew_or_die; or return $status

        while test (count $argv) -gt 0
            switch "$argv[1]"
                case -n --non-interactive
                    set -e argv[1]
                case '*'
                    break
            end
        end

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case in install
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "zypper install $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
            case rm remove
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "zypper remove $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
            case up update dup
                __g2b_308 "zypper $sub" "brew update && brew upgrade" __g2b_brew_update_upgrade
            case ref refresh
                __g2b_308 "zypper refresh" "brew update" __g2b_brew update
            case se search
                __g2b_308 "zypper search $s" "brew search $s" __g2b_brew search $argv
            case info
                __g2b_308 "zypper info $s" "brew info $s" __g2b_brew info $argv
            case clean
                __g2b_308 "zypper clean" "brew cleanup" __g2b_brew cleanup
            case '*'
                __g2b_301 "zypper $sub $s" "brew help"
                printf 'Run manually if intended: brew help\n' >&2
        end
    end

    function __g2b_apk
        __g2b_brew_or_die; or return $status

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case add
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "apk add $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
            case del delete
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "apk del $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
            case update
                __g2b_308 "apk update" "brew update" __g2b_brew update
            case upgrade
                __g2b_308 "apk upgrade" "brew upgrade" __g2b_brew upgrade
            case search
                __g2b_308 "apk search $s" "brew search $s" __g2b_brew search $argv
            case info
                __g2b_308 "apk info $s" "brew info $s" __g2b_brew info $argv
            case cache
                __g2b_308 "apk cache $s" "brew cleanup" __g2b_brew cleanup
            case '*'
                __g2b_301 "apk $sub $s" "brew help"
                printf 'Run manually if intended: brew help\n' >&2
        end
    end

    function __g2b_xbps_install
        __g2b_brew_or_die; or return $status

        set -l s (__g2b_join $argv)

        if test "$argv[1]" = -Syu; or test "$argv[1]" = -Su
            __g2b_308 "xbps-install $s" "brew update && brew upgrade" __g2b_brew_update_upgrade
        else
            __g2b_pkg_clean $argv
            set s (__g2b_join $__G2B_PKG_ARGS)
            __g2b_308 "xbps-install $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
        end
    end

    function __g2b_xbps_remove
        __g2b_brew_or_die; or return $status
        __g2b_pkg_clean $argv
        set -l s (__g2b_join $__G2B_PKG_ARGS)
        __g2b_308 "xbps-remove $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
    end

    function __g2b_emerge
        __g2b_brew_or_die; or return $status

        set -l sub "$argv[1]"
        set -l s (__g2b_join $argv)

        switch "$sub"
            case --sync
                __g2b_308 "emerge --sync" "brew update" __g2b_brew update
            case -C --unmerge
                set -e argv[1]
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "emerge --unmerge $s" "brew uninstall $s" __g2b_brew uninstall $__G2B_PKG_ARGS
            case -s --search
                set -e argv[1]
                set s (__g2b_join $argv)
                __g2b_308 "emerge --search $s" "brew search $s" __g2b_brew search $argv
            case '*'
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_308 "emerge $s" "brew install $s" __g2b_brew install $__G2B_PKG_ARGS
        end
    end

    function __g2b_snap
        __g2b_brew_or_die; or return $status

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case install
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_301 "snap install $s" "brew install --cask $s OR brew install $s"
                printf 'Snap names often do not match Homebrew formula/cask names.\n' >&2
                printf 'Try manually: brew search %s\n' "$s" >&2
            case remove purge
                __g2b_pkg_clean $argv
                set s (__g2b_join $__G2B_PKG_ARGS)
                __g2b_301 "snap $sub $s" "brew uninstall --cask $s OR brew uninstall $s"
            case list
                __g2b_301 "snap list" "brew list --cask && brew list"
            case find search
                __g2b_301 "snap $sub $s" "brew search --cask $s"
            case '*'
                __g2b_301 "snap $sub $s" "brew --cask"
        end
    end

    function __g2b_flatpak
        __g2b_brew_or_die; or return $status

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l last ""
        for a in $argv
            set last "$a"
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case install
                if test -z "$last"
                    __g2b_301 "flatpak install" "brew search --cask <name>"
                    return 64
                end

                __g2b_301 "flatpak install $s" "brew install --cask $last"
                printf 'Flatpak IDs often do not match Homebrew cask names.\n' >&2
                printf 'Try manually: brew search --cask %s\n' "$last" >&2
            case uninstall remove
                if test -z "$last"
                    __g2b_301 "flatpak $sub" "brew uninstall --cask <name>"
                    return 64
                end

                __g2b_301 "flatpak $sub $s" "brew uninstall --cask $last"
            case search
                __g2b_301 "flatpak search $s" "brew search --cask $s"
            case list
                __g2b_301 "flatpak list" "brew list --cask"
            case '*'
                __g2b_301 "flatpak $sub $s" "brew --cask"
        end
    end

    # ------------------------------------------------------------------------------
    # 3. Service management: systemd/service -> launchd/Homebrew services
    # ------------------------------------------------------------------------------

    function __g2b_brew_services_prefix
        if test "$GNU2BSD_SUDO" = 1
            printf 'sudo brew services'
        else
            printf 'brew services'
        end
    end

    function __g2b_brew_services_run
        if test "$GNU2BSD_SUDO" = 1
            command sudo (__g2b_brew_bin) services $argv
        else
            __g2b_brew services $argv
        end
    end

    function __g2b_brew_services_status
        set -l svc "$argv[1]"

        if test "$GNU2BSD_SUDO" = 1
            command sudo (__g2b_brew_bin) services list | grep "$svc"; or true
        else
            __g2b_brew services list | grep "$svc"; or true
        end
    end

    function __g2b_brew_services_is_active
        set -l svc "$argv[1]"

        if test "$GNU2BSD_SUDO" = 1
            command sudo (__g2b_brew_bin) services list | grep "$svc" | grep started >/dev/null
        else
            __g2b_brew services list | grep "$svc" | grep started >/dev/null
        end
    end

    function __g2b_systemctl
        __g2b_brew_or_die; or return $status

        if test "$argv[1]" = --user; or test "$argv[1]" = --system
            set -e argv[1]
        end

        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l svc "$argv[1]"
        set -l svc_clean (__g2b_svc_name "$svc")
        set -l brew_services (__g2b_brew_services_prefix)

        switch "$sub"
            case start
                __g2b_308 "systemctl start $svc" "$brew_services start $svc_clean" __g2b_brew_services_run start "$svc_clean"
            case stop
                __g2b_308 "systemctl stop $svc" "$brew_services stop $svc_clean" __g2b_brew_services_run stop "$svc_clean"
            case restart reload
                __g2b_308 "systemctl $sub $svc" "$brew_services restart $svc_clean" __g2b_brew_services_run restart "$svc_clean"
            case status
                __g2b_308 "systemctl status $svc" "$brew_services list | grep $svc_clean" __g2b_brew_services_status "$svc_clean"
            case enable
                __g2b_301 "systemctl enable $svc" "$brew_services start $svc_clean"
                printf 'Note: systemctl enable only enables startup. brew services start starts and registers the service.\n' >&2
                printf 'Run manually if intended: %s start %s\n' "$brew_services" "$svc_clean" >&2
            case disable
                __g2b_301 "systemctl disable $svc" "$brew_services stop $svc_clean"
                printf 'Note: systemctl disable only disables startup. brew services stop stops and unregisters the service.\n' >&2
                printf 'Run manually if intended: %s stop %s\n' "$brew_services" "$svc_clean" >&2
            case is-active
                __g2b_308 "systemctl is-active $svc" "$brew_services list | grep $svc_clean | grep started" __g2b_brew_services_is_active "$svc_clean"
            case list-units list-unit-files
                __g2b_308 "systemctl $sub" "$brew_services list" __g2b_brew_services_run list
            case daemon-reload
                __g2b_301 "systemctl daemon-reload" "brew services restart <service>"
                printf 'launchd does not use systemd unit reload semantics. Restart the specific brew service if needed.\n' >&2
            case cat edit
                __g2b_301 "systemctl $sub $svc" "$brew_services info $svc_clean"
                printf 'Run manually if intended: %s info %s\n' "$brew_services" "$svc_clean" >&2
            case '*'
                set -l s (__g2b_join $argv)
                __g2b_301 "systemctl $sub $s" "brew services {start|stop|restart|list|info}"
        end
    end

    function __g2b_service
        __g2b_brew_or_die; or return $status

        set -l svc "$argv[1]"
        set -l sub "$argv[2]"
        set -l svc_clean (__g2b_svc_name "$svc")
        set -l brew_services (__g2b_brew_services_prefix)

        if test -z "$svc"
            __g2b_308 service "$brew_services list" __g2b_brew_services_run list
            return
        end

        switch "$sub"
            case start
                __g2b_308 "service $svc start" "$brew_services start $svc_clean" __g2b_brew_services_run start "$svc_clean"
            case stop
                __g2b_308 "service $svc stop" "$brew_services stop $svc_clean" __g2b_brew_services_run stop "$svc_clean"
            case restart
                __g2b_308 "service $svc restart" "$brew_services restart $svc_clean" __g2b_brew_services_run restart "$svc_clean"
            case status
                __g2b_308 "service $svc status" "$brew_services list | grep $svc_clean" __g2b_brew_services_status "$svc_clean"
            case '*'
                set -l s (__g2b_join $argv)
                __g2b_301 "service $s" "brew services {start|stop|restart|list|info}"
        end
    end

    # ------------------------------------------------------------------------------
    # 4. Logs, tracing, dynamic linking
    # ------------------------------------------------------------------------------

    function __g2b_journalctl
        set -l args (__g2b_join $argv)

        if contains -- -f $argv
            __g2b_308 "journalctl $args" "log stream --style compact" log stream --style compact
        else if contains -- -b $argv
            __g2b_308 "journalctl -b" "log show --last boot --style compact" log show --last boot --style compact
        else if test "$argv[1]" = -u; and test -n "$argv[2]"
            set -l unit (__g2b_svc_name "$argv[2]")
            __g2b_301 "journalctl -u $argv[2]" "log show --predicate 'process CONTAINS \"$unit\"' --last 1h"
            printf 'macOS logs are not organized by systemd units. Run manually if intended:\n' >&2
            printf '  log show --predicate '\''process CONTAINS "%s"'\'' --last 1h --style compact\n' "$unit" >&2
        else if contains -- -xe $argv
            __g2b_301 "journalctl -xe" "log show --last 30m --style compact"
        else
            __g2b_301 "journalctl $args" "log show --last 15m --style compact"
        end
    end

    function __g2b_dmesg
        set -l args (__g2b_join $argv)

        if contains -- -w $argv; or contains -- --follow $argv
            __g2b_308 "dmesg $args" "log stream --predicate 'processID == 0' --style compact" log stream --predicate 'processID == 0' --style compact
        else
            __g2b_301 "dmesg $args" "sudo log show --predicate 'processID == 0' --last 15m"
            printf 'Run manually if intended: sudo log show --predicate '\''processID == 0'\'' --last 15m --style compact\n' >&2
        end
    end

    function __g2b_strace
        set -l s (__g2b_join $argv)
        __g2b_301 "strace $s" "sudo dtruss $s"
        printf 'Run manually if intended: sudo dtruss %s\n' "$s" >&2
    end

    function __g2b_ltrace
        set -l s (__g2b_join $argv)
        __g2b_301 "ltrace $s" "dtruss / dtrace"
        printf 'macOS does not provide a safe 1:1 ltrace equivalent.\n' >&2
    end

    function __g2b_ldd
        if test (count $argv) -eq 0
            __g2b_301 ldd "otool -L <binary>"
            return 64
        end

        set -l s (__g2b_join $argv)
        __g2b_308 "ldd $s" "otool -L $s" otool -L $argv
    end

    # ------------------------------------------------------------------------------
    # 5. /proc, /sys, and Linux file habits
    # ------------------------------------------------------------------------------

    function __g2b_cat
        if test (count $argv) -eq 1
            switch "$argv[1]"
                case /proc/cpuinfo
                    __g2b_redirect_msg 308 "cat /proc/cpuinfo" "sysctl -a | grep machdep.cpu"
                    sysctl -a | grep machdep.cpu
                    return 0
                case /proc/meminfo
                    __g2b_redirect_msg 308 "cat /proc/meminfo" "vm_stat && sysctl hw.memsize"
                    vm_stat
                    sysctl hw.memsize
                    return 0
                case /proc/version
                    __g2b_308 "cat /proc/version" "uname -a" uname -a
                    return 0
                case /proc/uptime
                    __g2b_308 "cat /proc/uptime" "sysctl -n kern.boottime" sysctl -n kern.boottime
                    return 0
                case /proc/loadavg
                    __g2b_308 "cat /proc/loadavg" "sysctl -n vm.loadavg" sysctl -n vm.loadavg
                    return 0
                case /proc/mounts
                    __g2b_308 "cat /proc/mounts" mount mount
                    return 0
                case /proc/partitions
                    __g2b_308 "cat /proc/partitions" "diskutil list" diskutil list
                    return 0
                case /etc/os-release
                    __g2b_redirect_msg 308 "cat /etc/os-release" sw_vers
                    printf 'NAME="macOS"\n'
                    printf 'VERSION="%s"\n' (sw_vers -productVersion)
                    printf 'ID=macos\n'
                    printf 'PRETTY_NAME="macOS %s"\n' (sw_vers -productVersion)
                    return 0
            end
        end

        command cat $argv
    end

    function __g2b_free
        set -l s (__g2b_join $argv)
        __g2b_redirect_msg 308 "free $s" "vm_stat && sysctl hw.memsize"
        printf 'Total memory:\n'
        sysctl hw.memsize
        printf '\nVM stats:\n'
        vm_stat
        printf '\nTop summary:\n'
        top -l 1 -s 0 | grep PhysMem
    end

    # ------------------------------------------------------------------------------
    # 6. Hardware and diagnostics
    # ------------------------------------------------------------------------------

    function __g2b_lsblk
        set -l s (__g2b_join $argv)
        __g2b_308 "lsblk $s" "diskutil list" diskutil list
    end

    function __g2b_blkid
        set -l s (__g2b_join $argv)
        __g2b_301 "blkid $s" "diskutil info -all"
        printf 'blkid and diskutil info do not have identical output formats.\n' >&2
        printf 'Run manually if intended: diskutil info -all\n' >&2
    end

    function __g2b_fdisk
        set -l s (__g2b_join $argv)

        if test "$argv[1]" = -l; or test "$argv[1]" = --list
            __g2b_308 "fdisk $s" "diskutil list" diskutil list
        else
            command fdisk $argv
        end
    end

    function __g2b_lsusb
        set -l s (__g2b_join $argv)
        __g2b_308 "lsusb $s" "system_profiler SPUSBDataType" system_profiler SPUSBDataType
    end

    function __g2b_lspci
        set -l s (__g2b_join $argv)
        __g2b_308 "lspci $s" "system_profiler SPPCIDataType" system_profiler SPPCIDataType
    end

    function __g2b_lsnvme
        set -l s (__g2b_join $argv)
        __g2b_308 "lsnvme $s" "system_profiler SPNVMeDataType" system_profiler SPNVMeDataType
    end

    function __g2b_lscpu
        set -l s (__g2b_join $argv)
        __g2b_redirect_msg 308 "lscpu $s" "sysctl -a | grep machdep.cpu"
        sysctl -a | grep machdep.cpu
    end

    function __g2b_lshw
        set -l s (__g2b_join $argv)
        __g2b_308 "lshw $s" "system_profiler SPHardwareDataType" system_profiler SPHardwareDataType
    end

    function __g2b_lsmem
        set -l s (__g2b_join $argv)
        __g2b_308 "lsmem $s" "system_profiler SPMemoryDataType" system_profiler SPMemoryDataType
    end

    function __g2b_dmidecode
        set -l s (__g2b_join $argv)
        __g2b_301 "dmidecode $s" "system_profiler SPHardwareDataType"
        printf 'Run manually if intended: system_profiler SPHardwareDataType\n' >&2
    end

    function __g2b_inxi
        set -l s (__g2b_join $argv)
        __g2b_301 "inxi $s" "system_profiler SPHardwareDataType SPSoftwareDataType SPDisplaysDataType"
        printf 'Run manually if intended: system_profiler SPHardwareDataType SPSoftwareDataType SPDisplaysDataType\n' >&2
    end

    function __g2b_acpi
        set -l s (__g2b_join $argv)
        __g2b_308 "acpi $s" "pmset -g batt" pmset -g batt
    end

    function __g2b_upower
        set -l s (__g2b_join $argv)
        __g2b_301 "upower $s" "pmset -g batt"
        printf 'Run manually if intended: pmset -g batt\n' >&2
    end

    function __g2b_sensors
        set -l s (__g2b_join $argv)
        __g2b_301 "sensors $s" "sudo powermetrics --samplers smc -n 1"
        printf 'Run manually if intended: sudo powermetrics --samplers smc -n 1\n' >&2
    end

    function __g2b_lswifi
        __g2b_308 lswifi "system_profiler SPAirPortDataType" system_profiler SPAirPortDataType
    end

    function __g2b_lsnet
        __g2b_308 lsnet "system_profiler SPNetworkDataType" system_profiler SPNetworkDataType
    end

    function __g2b_lsdisplay
        __g2b_308 lsdisplay "system_profiler SPDisplaysDataType" system_profiler SPDisplaysDataType
    end

    function __g2b_xrandr
        set -l s (__g2b_join $argv)
        __g2b_301 "xrandr $s" "system_profiler SPDisplaysDataType"
        printf 'macOS display control is not safely 1:1 compatible with xrandr.\n' >&2
        printf 'Run manually if intended: system_profiler SPDisplaysDataType\n' >&2
    end

    # ------------------------------------------------------------------------------
    # 7. Networking muscle memory
    # ------------------------------------------------------------------------------

    function __g2b_ip
        set -l brew_ip ""

        if set -q HOMEBREW_PREFIX; and test -x "$HOMEBREW_PREFIX/bin/ip"
            set brew_ip "$HOMEBREW_PREFIX/bin/ip"
        else if command -sq ip
            set brew_ip (command -s ip)
        end

        set -l s (__g2b_join $argv)

        if test -n "$brew_ip"
            __g2b_308 "ip $s" "$brew_ip $s" "$brew_ip" $argv
            return
        end

        switch "$argv[1]"
            case a addr address
                __g2b_308 "ip $s" ifconfig ifconfig
            case link
                __g2b_308 "ip link" ifconfig ifconfig
            case route r
                __g2b_308 "ip route" "netstat -rn" netstat -rn
            case neigh neighbor
                __g2b_308 "ip neigh" "arp -a" arp -a
            case '*'
                __g2b_301 "ip $s" "ifconfig / netstat -rn / arp -a"
                printf 'Install iproute2mac for better ip-command compatibility: brew install iproute2mac\n' >&2
        end
    end

    function __g2b_ss
        set -l args (__g2b_join $argv)

        if string match -q '*-tulpn*' -- "$args"; or string match -q '*-plnt*' -- "$args"; or string match -q '*-ltnp*' -- "$args"
            __g2b_308 "ss $args" "sudo lsof -iTCP -sTCP:LISTEN -P -n" command sudo lsof -iTCP -sTCP:LISTEN -P -n
        else if string match -q '*-tunap*' -- "$args"; or string match -q '*-tuna*' -- "$args"
            __g2b_308 "ss $args" "sudo lsof -i -P -n" command sudo lsof -i -P -n
        else
            __g2b_301 "ss $args" "netstat -anv"
            printf 'Run manually if intended: netstat -anv\n' >&2
        end
    end

    function __g2b_iwconfig
        set -l s (__g2b_join $argv)
        __g2b_301 "iwconfig $s" "networksetup -listallhardwareports && system_profiler SPAirPortDataType"
    end

    function __g2b_iw
        set -l s (__g2b_join $argv)
        __g2b_301 "iw $s" "system_profiler SPAirPortDataType"
    end

    function __g2b_nmcli
        set -l s (__g2b_join $argv)
        __g2b_301 "nmcli $s" networksetup
        printf 'macOS does not use NetworkManager. Try: networksetup -listallhardwareports\n' >&2
    end

    function __g2b_resolvectl
        set -l s (__g2b_join $argv)
        __g2b_301 "resolvectl $s" "scutil --dns"
        printf 'Run manually if intended: scutil --dns\n' >&2
    end

    function __g2b_systemd_resolve
        __g2b_resolvectl $argv
    end

    function __g2b_digflush
        __g2b_308 "systemd-resolve --flush-caches" "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder" sh -c 'sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder'
    end

    function __g2b_netplan
        set -l s (__g2b_join $argv)
        __g2b_301 "netplan $s" "networksetup / System Settings > Network"
        printf 'macOS does not use netplan. Try: networksetup -listallhardwareports\n' >&2
    end

    function __g2b_ifup
        set -l s (__g2b_join $argv)
        __g2b_301 "ifup $s" "networksetup -setnetworkserviceenabled <service> on"
    end

    function __g2b_ifdown
        set -l s (__g2b_join $argv)
        __g2b_301 "ifdown $s" "networksetup -setnetworkserviceenabled <service> off"
    end

    # ------------------------------------------------------------------------------
    # 8. Firewall redirects
    # ------------------------------------------------------------------------------

    function __g2b_ufw
        set -l sub ""
        if test (count $argv) -gt 0
            set sub "$argv[1]"
            set -e argv[1]
        end

        set -l s (__g2b_join $argv)

        switch "$sub"
            case status
                __g2b_301 "ufw status" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate"
            case enable
                __g2b_301 "ufw enable" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
            case disable
                __g2b_301 "ufw disable" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off"
            case app
                __g2b_301 "ufw app $s" "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps"
            case '*'
                __g2b_301 "ufw $sub $s" "socketfilterfw / pfctl"
        end
    end

    function __g2b_iptables
        set -l s (__g2b_join $argv)

        if test "$argv[1]" = -L; or test "$argv[1]" = --list
            __g2b_301 "iptables $s" "sudo pfctl -sr"
        else
            __g2b_301 "iptables $s" pfctl
        end

        printf 'Not auto-executing because iptables and pf rules are not safely 1:1 compatible.\n' >&2
    end

    function __g2b_nft
        set -l s (__g2b_join $argv)
        __g2b_301 "nft $s" pfctl
        printf 'Not auto-executing because nftables and pf rules are not safely 1:1 compatible.\n' >&2
    end

    function __g2b_firewall_cmd
        set -l s (__g2b_join $argv)
        __g2b_301 "firewall-cmd $s" "socketfilterfw / pfctl"
    end

    # ------------------------------------------------------------------------------
    # 9. Desktop/Linux GUI helpers
    # ------------------------------------------------------------------------------

    function __g2b_xdg_open
        set -l s (__g2b_join $argv)
        __g2b_308 "xdg-open $s" "open $s" open $argv
    end

    function __g2b_sensible_browser
        set -l s (__g2b_join $argv)
        __g2b_308 "sensible-browser $s" "open $s" open $argv
    end

    function __g2b_gio
        if test "$argv[1]" = open
            set -e argv[1]
            set -l s (__g2b_join $argv)
            __g2b_308 "gio open $s" "open $s" open $argv
        else
            set -l s (__g2b_join $argv)
            __g2b_301 "gio $s" open
        end
    end

    function __g2b_nautilus
        set -l s (__g2b_join $argv)
        test -n "$s"; or set s "."
        __g2b_301 "nautilus $s" "open $s"
        printf 'Run manually if intended: open %s\n' "$s" >&2
    end

    function __g2b_dolphin
        set -l s (__g2b_join $argv)
        test -n "$s"; or set s "."
        __g2b_301 "dolphin $s" "open $s"
        printf 'Run manually if intended: open %s\n' "$s" >&2
    end

    function __g2b_thunar
        set -l s (__g2b_join $argv)
        test -n "$s"; or set s "."
        __g2b_301 "thunar $s" "open $s"
        printf 'Run manually if intended: open %s\n' "$s" >&2
    end

    function __g2b_notify_send
        set -l title Notification
        if test (count $argv) -gt 0
            set title "$argv[1]"
            set -e argv[1]
        end

        set -l body (__g2b_join $argv)

        __g2b_301 "notify-send $title $body" "osascript display notification"
        printf 'Run manually if intended:\n' >&2
        printf '  osascript -e '\''display notification "%s" with title "%s"'\''\n' "$body" "$title" >&2
    end

    function __g2b_xclip
        set -l s (__g2b_join $argv)

        if contains -- -o $argv
            __g2b_308 "xclip $s" pbpaste pbpaste
        else
            __g2b_308 "xclip $s" pbcopy pbcopy
        end
    end

    function __g2b_xsel
        set -l s (__g2b_join $argv)

        if contains -- -o $argv
            __g2b_308 "xsel $s" pbpaste pbpaste
        else
            __g2b_308 "xsel $s" pbcopy pbcopy
        end
    end

    function __g2b_wl_copy
        __g2b_308 wl-copy pbcopy pbcopy
    end

    function __g2b_wl_paste
        __g2b_308 wl-paste pbpaste pbpaste
    end

    # ------------------------------------------------------------------------------
    # 10. Kernel module / bootloader commands
    # ------------------------------------------------------------------------------

    function __g2b_lsmod
        __g2b_301 lsmod "kmutil showloaded"
        printf 'Run manually if intended: kmutil showloaded\n' >&2
    end

    function __g2b_modprobe
        set -l s (__g2b_join $argv)
        __g2b_301 "modprobe $s" "kmutil / kextload"
        printf 'Not auto-loading kernel extensions because Linux modules and macOS kexts are not safely 1:1 compatible.\n' >&2
    end

    function __g2b_insmod
        set -l s (__g2b_join $argv)
        __g2b_301 "insmod $s" "kmutil / kextload"
        printf 'Not auto-loading kernel extensions because Linux modules and macOS kexts are not safely 1:1 compatible.\n' >&2
    end

    function __g2b_rmmod
        set -l s (__g2b_join $argv)
        __g2b_301 "rmmod $s" "kmutil / kextunload"
        printf 'Not auto-unloading kernel extensions because Linux modules and macOS kexts are not safely 1:1 compatible.\n' >&2
    end

    function __g2b_update_grub
        __g2b_301 update-grub "not applicable on normal macOS boot"
        printf 'macOS does not use GRUB for normal boot management.\n' >&2
    end

    function __g2b_grub_install
        set -l s (__g2b_join $argv)
        __g2b_301 "grub-install $s" "not applicable on normal macOS boot"
        printf 'macOS does not use GRUB for normal boot management.\n' >&2
    end

    function __g2b_update_initramfs
        set -l s (__g2b_join $argv)
        __g2b_301 "update-initramfs $s" "not applicable on macOS"
    end

    function __g2b_mkinitcpio
        set -l s (__g2b_join $argv)
        __g2b_301 "mkinitcpio $s" "not applicable on macOS"
    end

    function __g2b_dracut
        set -l s (__g2b_join $argv)
        __g2b_301 "dracut $s" "not applicable on macOS"
    end

    # ------------------------------------------------------------------------------
    # 11. Power commands
    # ------------------------------------------------------------------------------

    function __g2b_reboot
        __g2b_301 reboot "sudo shutdown -r now"
        printf 'Run manually if intended: sudo shutdown -r now\n' >&2
    end

    function __g2b_poweroff
        __g2b_301 poweroff "sudo shutdown -h now"
        printf 'Run manually if intended: sudo shutdown -h now\n' >&2
    end

    function __g2b_halt
        __g2b_301 halt "sudo shutdown -h now"
        printf 'Run manually if intended: sudo shutdown -h now\n' >&2
    end

    function __g2b_init
        set -l s (__g2b_join $argv)

        switch "$argv[1]"
            case 0
                __g2b_301 "init 0" "sudo shutdown -h now"
                printf 'Run manually if intended: sudo shutdown -h now\n' >&2
            case 6
                __g2b_301 "init 6" "sudo shutdown -r now"
                printf 'Run manually if intended: sudo shutdown -r now\n' >&2
            case '*'
                __g2b_301 "init $s" "launchd has no SysV runlevels"
        end
    end

    # ------------------------------------------------------------------------------
    # 12. Host / time / system info
    # ------------------------------------------------------------------------------

    function __g2b_hostnamectl
        set -l s (__g2b_join $argv)
        __g2b_redirect_msg 308 "hostnamectl $s" "scutil / sw_vers / uname"

        printf 'Static hostname: %s\n' (scutil --get ComputerName 2>/dev/null)
        printf 'Operating System: macOS %s\n' (sw_vers -productVersion)
        printf 'Kernel: Darwin %s\n' (uname -r)
        printf 'Architecture: %s\n' (uname -m)
    end

    function __g2b_timedatectl
        set -l s (__g2b_join $argv)
        __g2b_redirect_msg 308 "timedatectl $s" "systemsetup -gettimezone / date"

        printf 'Local time: %s\n' (date)
        printf 'Time zone: '
        systemsetup -gettimezone 2>/dev/null | sed 's/Time Zone: //'
    end

    function __g2b_localectl
        set -l s (__g2b_join $argv)
        __g2b_301 "localectl $s" "defaults read -g AppleLocale"
        printf 'Run manually if intended: defaults read -g AppleLocale\n' >&2
    end

    function __g2b_loginctl
        set -l s (__g2b_join $argv)
        __g2b_301 "loginctl $s" "launchctl / who"
        printf 'macOS launchd/login sessions do not map cleanly to systemd-logind.\n' >&2
    end

    function __g2b_nproc
        __g2b_308 nproc "sysctl -n hw.ncpu" sysctl -n hw.ncpu
    end

    function __g2b_pidof
        set -l s (__g2b_join $argv)
        __g2b_308 "pidof $s" "pgrep -x $s" pgrep -x $argv
    end

    # ------------------------------------------------------------------------------
    # 13. user/group commands: teach only
    # ------------------------------------------------------------------------------

    function __g2b_useradd
        set -l s (__g2b_join $argv)
        __g2b_301 "useradd $s" "sysadminctl -addUser / dscl"
        printf 'Not auto-executing. macOS user creation needs different required fields.\n' >&2
        printf 'Example: sudo sysadminctl -addUser USERNAME -fullName "Full Name" -password -\n' >&2
    end

    function __g2b_adduser
        __g2b_useradd $argv
    end

    function __g2b_usermod
        set -l s (__g2b_join $argv)
        __g2b_301 "usermod $s" dscl
        printf 'Not auto-executing. Linux usermod flags do not map safely to macOS dscl.\n' >&2
    end

    function __g2b_userdel
        set -l s (__g2b_join $argv)
        __g2b_301 "userdel $s" "sysadminctl -deleteUser / dscl"
        printf 'Not auto-executing user deletion.\n' >&2
    end

    function __g2b_groupadd
        set -l s (__g2b_join $argv)
        __g2b_301 "groupadd $s" "dscl . -create /Groups/GROUP"
        printf 'Not auto-executing group creation.\n' >&2
    end

    function __g2b_groupdel
        set -l s (__g2b_join $argv)
        __g2b_301 "groupdel $s" "dscl . -delete /Groups/GROUP"
        printf 'Not auto-executing group deletion.\n' >&2
    end

    # ------------------------------------------------------------------------------
    # 14. SELinux/AppArmor-ish concepts
    # ------------------------------------------------------------------------------

    function __g2b_getenforce
        __g2b_301 getenforce "csrutil status"
        printf 'SELinux is not used by macOS. SIP is the closest security-mode concept.\n' >&2
        printf 'Run manually if intended: csrutil status\n' >&2
    end

    function __g2b_setenforce
        set -l s (__g2b_join $argv)
        __g2b_301 "setenforce $s" "csrutil enable/disable from Recovery"
        printf 'Not auto-executing. SIP changes require macOS Recovery.\n' >&2
    end

    function __g2b_aa_status
        __g2b_301 aa-status "not applicable; macOS does not use AppArmor"
    end

    # ------------------------------------------------------------------------------
    # 15. Pass-through proxies: cat, sudo
    # ------------------------------------------------------------------------------

    function cat
        __g2b_cat $argv
    end

    function sudo
        set -l cmd "$argv[1]"

        switch "$cmd"
            case apt apt-get
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_apt $argv
            case apt-cache
                set -e argv[1]
                __g2b_note "dropping sudo"
                __g2b_apt_cache $argv
            case pacman
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_pacman $argv
            case dnf yum
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_dnf $argv
            case zypper
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_zypper $argv
            case apk
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_apk $argv
            case xbps-install
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_xbps_install $argv
            case xbps-remove
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_xbps_remove $argv
            case emerge
                set -e argv[1]
                __g2b_note "dropping sudo because Homebrew should not run as root"
                __g2b_emerge $argv
            case snap
                set -e argv[1]
                __g2b_note "dropping sudo"
                __g2b_snap $argv
            case flatpak
                set -e argv[1]
                __g2b_note "dropping sudo"
                __g2b_flatpak $argv
            case systemctl systemd
                set -e argv[1]
                env GNU2BSD_SUDO=1 fish -c "__g2b_systemctl $argv"
            case service
                set -e argv[1]
                env GNU2BSD_SUDO=1 fish -c "__g2b_service $argv"
            case '*'
                command sudo $argv
        end
    end

    # ------------------------------------------------------------------------------
    # 16. Fat-finger command-not-found redirects
    # ------------------------------------------------------------------------------

    function __g2b_typo
        set -l cmd "$argv[1]"
        set -e argv[1]
        set -l s (__g2b_join $argv)

        switch "$cmd"
            case aptt aptget apt-gte apt-gat
                __g2b_redirect_msg 308 "$cmd $s" "apt $s"
                __g2b_apt $argv
            case pacamn packman pacmn pacmam
                __g2b_redirect_msg 308 "$cmd $s" "pacman $s"
                __g2b_pacman $argv
            case dnf5 dnff ymu yumm
                __g2b_redirect_msg 308 "$cmd $s" "dnf $s"
                __g2b_dnf $argv
            case zyppr zyper zyppe
                __g2b_redirect_msg 308 "$cmd $s" "zypper $s"
                __g2b_zypper $argv
            case systemclt systmctl sytemctl systemct systemctrl sysctlctl
                __g2b_redirect_msg 308 "$cmd $s" "systemctl $s"
                __g2b_systemctl $argv
            case journalclt journactl journalct jounalctl
                __g2b_redirect_msg 308 "$cmd $s" "journalctl $s"
                __g2b_journalctl $argv
            case '*'
                return 127
        end
    end

    function fish_command_not_found
        __g2b_typo $argv
        or begin
            printf 'fish: Unknown command: %s\n' "$argv[1]" >&2
            return 127
        end
    end

    # ------------------------------------------------------------------------------
    # 17. Apply mappings
    # Most commands map only if missing.
    # cat/sudo are intentional pass-through functions.
    # fdisk/dmesg/ldd are force-wrapped because macOS/native behavior differs enough.
    # ------------------------------------------------------------------------------

    __g2b_map_if_missing apt __g2b_apt
    __g2b_map_if_missing apt-get __g2b_apt
    __g2b_map_if_missing apt-cache __g2b_apt_cache
    __g2b_map_if_missing add-apt-repository __g2b_add_apt_repository

    __g2b_map_if_missing pacman __g2b_pacman
    __g2b_map_if_missing yay __g2b_yay
    __g2b_map_if_missing paru __g2b_paru
    __g2b_map_if_missing dnf __g2b_dnf
    __g2b_map_if_missing yum __g2b_dnf
    __g2b_map_if_missing zypper __g2b_zypper
    __g2b_map_if_missing apk __g2b_apk
    __g2b_map_if_missing xbps-install __g2b_xbps_install
    __g2b_map_if_missing xbps-remove __g2b_xbps_remove
    __g2b_map_if_missing emerge __g2b_emerge
    __g2b_map_if_missing snap __g2b_snap
    __g2b_map_if_missing flatpak __g2b_flatpak

    __g2b_map_if_missing systemctl __g2b_systemctl
    __g2b_map_if_missing systemd __g2b_systemctl
    __g2b_map_if_missing service __g2b_service

    __g2b_map_if_missing journalctl __g2b_journalctl
    __g2b_map_if_missing strace __g2b_strace
    __g2b_map_if_missing ltrace __g2b_ltrace

    __g2b_map_if_missing free __g2b_free
    __g2b_map_if_missing lsblk __g2b_lsblk
    __g2b_map_if_missing blkid __g2b_blkid
    __g2b_map_if_missing lsusb __g2b_lsusb
    __g2b_map_if_missing lspci __g2b_lspci
    __g2b_map_if_missing lsnvme __g2b_lsnvme
    __g2b_map_if_missing lscpu __g2b_lscpu
    __g2b_map_if_missing lshw __g2b_lshw
    __g2b_map_if_missing lsmem __g2b_lsmem
    __g2b_map_if_missing dmidecode __g2b_dmidecode
    __g2b_map_if_missing inxi __g2b_inxi
    __g2b_map_if_missing acpi __g2b_acpi
    __g2b_map_if_missing upower __g2b_upower
    __g2b_map_if_missing sensors __g2b_sensors
    __g2b_map_if_missing lswifi __g2b_lswifi
    __g2b_map_if_missing lsnet __g2b_lsnet
    __g2b_map_if_missing lsdisplay __g2b_lsdisplay
    __g2b_map_if_missing xrandr __g2b_xrandr

    __g2b_map_if_missing ip __g2b_ip
    __g2b_map_if_missing ss __g2b_ss
    __g2b_map_if_missing iwconfig __g2b_iwconfig
    __g2b_map_if_missing iw __g2b_iw
    __g2b_map_if_missing nmcli __g2b_nmcli
    __g2b_map_if_missing resolvectl __g2b_resolvectl
    __g2b_map_if_missing systemd-resolve __g2b_systemd_resolve
    __g2b_map_if_missing digflush __g2b_digflush
    __g2b_map_if_missing netplan __g2b_netplan
    __g2b_map_if_missing ifup __g2b_ifup
    __g2b_map_if_missing ifdown __g2b_ifdown

    __g2b_map_if_missing ufw __g2b_ufw
    __g2b_map_if_missing iptables __g2b_iptables
    __g2b_map_if_missing nft __g2b_nft
    __g2b_map_if_missing firewall-cmd __g2b_firewall_cmd

    __g2b_map_if_missing xdg-open __g2b_xdg_open
    __g2b_map_if_missing sensible-browser __g2b_sensible_browser
    __g2b_map_if_missing gio __g2b_gio
    __g2b_map_if_missing nautilus __g2b_nautilus
    __g2b_map_if_missing dolphin __g2b_dolphin
    __g2b_map_if_missing thunar __g2b_thunar
    __g2b_map_if_missing notify-send __g2b_notify_send
    __g2b_map_if_missing xclip __g2b_xclip
    __g2b_map_if_missing xsel __g2b_xsel
    __g2b_map_if_missing wl-copy __g2b_wl_copy
    __g2b_map_if_missing wl-paste __g2b_wl_paste

    __g2b_map_if_missing lsmod __g2b_lsmod
    __g2b_map_if_missing modprobe __g2b_modprobe
    __g2b_map_if_missing insmod __g2b_insmod
    __g2b_map_if_missing rmmod __g2b_rmmod
    __g2b_map_if_missing update-grub __g2b_update_grub
    __g2b_map_if_missing grub-install __g2b_grub_install
    __g2b_map_if_missing update-initramfs __g2b_update_initramfs
    __g2b_map_if_missing mkinitcpio __g2b_mkinitcpio
    __g2b_map_if_missing dracut __g2b_dracut

    __g2b_map_if_missing poweroff __g2b_poweroff
    __g2b_map_if_missing init __g2b_init

    __g2b_map_if_missing hostnamectl __g2b_hostnamectl
    __g2b_map_if_missing timedatectl __g2b_timedatectl
    __g2b_map_if_missing localectl __g2b_localectl
    __g2b_map_if_missing loginctl __g2b_loginctl
    __g2b_map_if_missing nproc __g2b_nproc
    __g2b_map_if_missing pidof __g2b_pidof

    __g2b_map_if_missing useradd __g2b_useradd
    __g2b_map_if_missing adduser __g2b_adduser
    __g2b_map_if_missing usermod __g2b_usermod
    __g2b_map_if_missing userdel __g2b_userdel
    __g2b_map_if_missing groupadd __g2b_groupadd
    __g2b_map_if_missing groupdel __g2b_groupdel

    __g2b_map_if_missing getenforce __g2b_getenforce
    __g2b_map_if_missing setenforce __g2b_setenforce
    __g2b_map_if_missing aa-status __g2b_aa_status

    function fdisk
        __g2b_fdisk $argv
    end

    function dmesg
        __g2b_dmesg $argv
    end

    function ldd
        __g2b_ldd $argv
    end

    # ------------------------------------------------------------------------------
    # 18. Help
    # ------------------------------------------------------------------------------

    function gnu2bsd-help
        echo 'gnu2bsd examples:'
        echo ''
        echo '308 = close-enough redirect, then execute:'
        echo 'apt install wget -> brew install wget'
        echo 'sudo apt update -> apt update, root dropped'
        echo 'pacman -Syu -> brew update && brew upgrade'
        echo 'dnf install htop -> brew install htop'
        echo 'zypper in jq -> brew install jq'
        echo 'apk add curl -> brew install curl'
        echo ''
        echo 'systemctl start nginx -> brew services start nginx'
        echo 'sudo systemctl start nginx -> sudo brew services start nginx'
        echo 'service nginx restart -> brew services restart nginx'
        echo 'journalctl -f -> log stream --style compact'
        echo 'journalctl -b -> log show --last boot'
        echo ''
        echo 'lsblk -> diskutil list'
        echo 'lsusb -> system_profiler SPUSBDataType'
        echo 'lspci -> system_profiler SPPCIDataType'
        echo 'lscpu -> sysctl -a | grep machdep.cpu'
        echo 'free -h -> vm_stat + memory summary'
        echo 'cat /proc/cpuinfo -> sysctl CPU info'
        echo 'cat /etc/os-release -> sw_vers-style macOS info'
        echo ''
        echo 'ip addr -> iproute2mac ip OR ifconfig fallback'
        echo 'ss -tulpn -> sudo lsof -iTCP -sTCP:LISTEN -P -n'
        echo 'xdg-open file -> open file'
        echo 'xclip / xsel -> pbcopy / pbpaste'
        echo 'ldd binary -> otool -L binary'
        echo ''
        echo '301 = conceptual redirect, teach only, do not execute:'
        echo 'iptables -> pfctl'
        echo 'nft -> pfctl'
        echo 'ufw -> socketfilterfw / pfctl'
        echo 'snap -> brew casks/formulas'
        echo 'flatpak -> brew casks'
        echo 'modprobe -> kmutil / kextload'
        echo 'useradd/usermod/userdel -> sysadminctl / dscl'
        echo 'setenforce/getenforce -> csrutil / SIP'
    end
end
# <<< linuxify <<<
FISHBLOCK
	ok "Added Linuxify GNU-tools block to ~/.config/fish/config.fish"
else
	ok "Linuxify GNU-tools block already in ~/.config/fish/config.fish"
fi

printf '\n%s%s==== GNU > BSD fully configured! ====%s\n' "$BOLD" "$GRN" "$RST"
