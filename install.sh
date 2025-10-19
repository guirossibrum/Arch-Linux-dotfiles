#!/usr/bin/env bash

# Exit on any error and catch pipe failures
set -e
set -o pipefail

# ----------------------
# Variables
# ----------------------
DOTFILES_DIR="$HOME/dotfiles"
REPO_URL="https://github.com/guirossibrum/Arch-Linux-dotfiles.git"
INSTALL_PACKAGES_FILE="$DOTFILES_DIR/install_packages.txt"
UNINSTALL_PACKAGES_FILE="$DOTFILES_DIR/uninstall_packages.txt"

# ----------------------
# Logging functions
# ----------------------
log() { echo -e "[INFO] $*"; }
error() { echo -e "[ERROR] $*" >&2; }

# ----------------------
# Pre-checks
# ----------------------
if ! command -v git &> /dev/null; then
    error "git is not installed. Please install git first."
    exit 1
fi

if ! command -v pacman &> /dev/null; then
    error "pacman is not installed. This script is designed for Arch Linux."
    exit 1
fi

# Check for an AUR helper
AUR_HELPER=""
if command -v yay &> /dev/null; then
    AUR_HELPER="yay"
elif command -v paru &> /dev/null; then
    AUR_HELPER="paru"
else
    log "No AUR helper (yay or paru) found. AUR packages will be skipped."
fi

# ----------------------
# Clone dotfiles repo (handling existing folder)
# ----------------------
if [ -d "$DOTFILES_DIR" ]; then
    log "Dotfiles directory already exists at $DOTFILES_DIR"
    
    # Try to prompt the user via /dev/tty
    if [ -t 1 ]; then
        # Interactive: use /dev/tty for read
        read -rp "Do you want to delete the existing dotfiles folder and continue? [y/N] " confirm </dev/tty
        if [[ $confirm =~ ^[yY]$ ]]; then
            log "Deleting existing dotfiles folder..."
            rm -rf "$DOTFILES_DIR"
        else
            error "Aborting. Please remove or rename $DOTFILES_DIR manually."
            exit 1
        fi
    else
        # Non-interactive: automatically delete
        log "Non-interactive shell detected. Deleting existing dotfiles folder automatically..."
        rm -rf "$DOTFILES_DIR"
    fi
fi

log "Cloning dotfiles repository..."
git clone "$REPO_URL" "$DOTFILES_DIR"
cd "$DOTFILES_DIR"


# ----------------------
# Helper functions
# ----------------------

# Check if package exists in official repo
is_official_repo() {
    local pkg="$1"
    pacman -Si "$pkg" &> /dev/null
}

# Check if package is installed from official repo
is_official_installed() {
    local pkg="$1"
    pacman -Qi "$pkg" &> /dev/null
}

# Check if package is installed via AUR helper
is_aur_installed() {
    local pkg="$1"
    if [ -n "$AUR_HELPER" ]; then
        "$AUR_HELPER" -Q "$pkg" &> /dev/null
    else
        return 1
    fi
}

# Install package (official repo first, then AUR)
install_package() {
    local pkg="$1"

    if is_official_installed "$pkg" || is_aur_installed "$pkg"; then
        log "$pkg is already installed"
        return
    fi

    if is_official_repo "$pkg"; then
        log "Installing $pkg from official repositories..."
        if sudo pacman -S --noconfirm "$pkg"; then
            log "$pkg installed via pacman"
        else
            error "Failed to install $pkg via pacman"
        fi
    elif [ -n "$AUR_HELPER" ]; then
        log "Installing $pkg from AUR using $AUR_HELPER..."
        if "$AUR_HELPER" -S --noconfirm "$pkg"; then
            log "$pkg installed via $AUR_HELPER"
        else
            error "Failed to install $pkg via $AUR_HELPER"
        fi
    else
        error "$pkg not found in official repos and no AUR helper available"
    fi
}

# Uninstall package (official repo or AUR)
uninstall_package() {
    local pkg="$1"

    if is_official_installed "$pkg"; then
        log "Uninstalling $pkg from official repositories..."
        if sudo pacman -Rns --noconfirm "$pkg"; then
            log "$pkg successfully uninstalled via pacman"
        else
            error "Failed to uninstall $pkg via pacman"
        fi
    elif is_aur_installed "$pkg"; then
        log "Uninstalling $pkg from AUR via $AUR_HELPER..."
        if "$AUR_HELPER" -Rns --noconfirm "$pkg"; then
            log "$pkg successfully uninstalled via $AUR_HELPER"
        else
            error "Failed to uninstall $pkg via $AUR_HELPER"
        fi
    else
        log "$pkg is not installed, skipping"
    fi
}

# ----------------------
# Uninstall packages
# ----------------------
if [ -f "$UNINSTALL_PACKAGES_FILE" ]; then
    UNINSTALL_PACKAGES=()
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        UNINSTALL_PACKAGES+=("$line")
    done < "$UNINSTALL_PACKAGES_FILE"

    if [ "${#UNINSTALL_PACKAGES[@]}" -gt 0 ]; then
        log "The following packages will be uninstalled:"
        printf '  %s\n' "${UNINSTALL_PACKAGES[@]}"

        read -rp "Do you want to proceed with uninstallation? [y/N] " confirm
        if [[ $confirm =~ ^[yY]$ ]]; then
            for pkg in "${UNINSTALL_PACKAGES[@]}"; do
                uninstall_package "$pkg"
            done
        else
            log "Skipping uninstallation."
        fi
    else
        log "No packages listed for uninstallation."
    fi
else
    log "No uninstall_packages.txt found, skipping uninstallation step."
fi

# ----------------------
# Install packages
# ----------------------
if [ ! -f "$INSTALL_PACKAGES_FILE" ]; then
    error "install_packages.txt not found in $DOTFILES_DIR"
    exit 1
fi

INSTALL_PACKAGES=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    INSTALL_PACKAGES+=("$line")
done < "$INSTALL_PACKAGES_FILE"

for pkg in "${INSTALL_PACKAGES[@]}"; do
    install_package "$pkg"
done

# ----------------------
# Ensure stow is installed
# ----------------------
if ! command -v stow &> /dev/null; then
    error "stow is not installed and was not found in install_packages.txt"
    exit 1
fi

# ----------------------
# Deploy dotfiles using stow (using stow.txt)
# ----------------------

STOW_FILE="$DOTFILES_DIR/stow.txt"

if [ ! -f "$STOW_FILE" ]; then
    error "stow.txt not found in $DOTFILES_DIR"
    exit 1
fi

log "Preparing to stow dotfiles listed in stow.txt..."

# Read packages from stow.txt (ignore empty lines and comments)
STOW_PACKAGES=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    STOW_PACKAGES+=("$line")
done < "$STOW_FILE"

if [ "${#STOW_PACKAGES[@]}" -eq 0 ]; then
    error "No valid entries found in stow.txt"
    exit 1
fi

# --- helper: find all unique top-level target directories each package will affect ---
find_targets_for_pkg() {
    local pkg="$1"
    local pkgdir="$DOTFILES_DIR/$pkg"
    local -n _out_array=$2
    _out_array=()

    while IFS= read -r -d $'\0' entry; do
        rel="${entry#$pkgdir/}"
        [[ -z "$rel" ]] && continue
        top="${rel%%/*}"  # first part of the path, e.g., .config
        [[ -z "$top" ]] && continue
        target="$HOME/$top"
        local exists=0
        for t in "${_out_array[@]}"; do
            [[ "$t" == "$target" ]] && { exists=1; break; }
        done
        [[ $exists -eq 0 ]] && _out_array+=("$target")
    done < <(find "$pkgdir" -mindepth 1 -print0 2>/dev/null)
}

# --- gather all target directories ---
ALL_TARGETS=()
for pkg in "${STOW_PACKAGES[@]}"; do
    [ ! -d "$DOTFILES_DIR/$pkg" ] && { log "Skipping missing package: $pkg"; continue; }
    pkg_targets=()
    find_targets_for_pkg "$pkg" pkg_targets
    for t in "${pkg_targets[@]}"; do
        skip=0
        for existing in "${ALL_TARGETS[@]}"; do
            [[ "$existing" == "$t" ]] && { skip=1; break; }
        done
        [[ $skip -eq 0 ]] && ALL_TARGETS+=("$t")
    done
done

# --- back up existing directories before stowing ---
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [ "${#ALL_TARGETS[@]}" -gt 0 ]; then
    log "The following directories will be moved to backup before stowing:"
    printf '  %s\n' "${ALL_TARGETS[@]}"
    log "Backup location: $BACKUP_DIR"

    if [ -t 1 ]; then
        read -rp "Proceed to move these directories to backup? [y/N] " confirm </dev/tty
        if [[ ! $confirm =~ ^[yY]$ ]]; then
            error "User aborted."
            exit 1
        fi
    else
        log "Non-interactive shell detected — proceeding automatically."
    fi

    for t in "${ALL_TARGETS[@]}"; do
        if [ -e "$t" ]; then
            rel_path="${t#$HOME/}"
            dest_dir="$BACKUP_DIR/$rel_path"
            mkdir -p "$(dirname "$dest_dir")"
            log "Moving existing directory to backup: $t → $dest_dir"
            mv "$t" "$dest_dir"
        fi
    done
fi

# --- perform stow for each package ---
log "Starting stow process..."

for pkg in "${STOW_PACKAGES[@]}"; do
    if [ -d "$DOTFILES_DIR/$pkg" ]; then
        log "Stowing package: $pkg"
        if stow -d "$DOTFILES_DIR" -t "$HOME" "$pkg" 2>&1; then
            log "✅ Successfully stowed: $pkg"
        else
            error "❌ Failed to stow: $pkg"
            echo "----- Error output for $pkg -----"
            stow -d "$DOTFILES_DIR" -t "$HOME" "$pkg" 2>&1 || true
            echo "--------------------------------"
            continue
        fi
    else
        log "⚠️  Warning: package folder '$pkg' does not exist in dotfiles repo."
    fi
done

log "Dotfiles stowed successfully (errors above, if any, were skipped)."

