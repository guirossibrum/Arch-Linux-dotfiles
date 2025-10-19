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
# Clone dotfiles repo (with confirmation if it exists)
# ----------------------
if [ -d "$DOTFILES_DIR" ]; then
    log "Dotfiles directory already exists at $DOTFILES_DIR"
    read -rp "Do you want to delete the existing dotfiles folder and continue? [y/N] " confirm
    if [[ $confirm =~ ^[yY]$ ]]; then
        log "Deleting existing dotfiles folder..."
        rm -rf "$DOTFILES_DIR"
    else
        error "Aborting. Please remove or rename $DOTFILES_DIR manually."
        exit 1
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
# Deploy dotfiles using stow
# ----------------------
log "Installing dotfiles using stow..."

# Manual option: specify directories explicitly
stow starship
stow waybar
stow hyprland

# Automated option (iterate over each folder in dotfiles)
# Uncomment to test
# for dir in */ ; do
#     stow "${dir%/}"
# done

log "Dotfiles installation completed successfully!"
