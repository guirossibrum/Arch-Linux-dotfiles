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

# Check if package is in official Arch Repositories
is_official_repo() {
    local pkg="$1"
    # Check if package exists in official Arch repos
    pacman -Si "$pkg" &> /dev/null
}

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
# Clone dotfiles repo
# ----------------------
if [ -d "$DOTFILES_DIR" ]; then
    log "Dotfiles directory already exists at $DOTFILES_DIR"
    read -rp "Do you want to rename differing files with .bak and update with new repository? [y/N] " confirm
    if [[ $confirm =~ ^[yY]$ ]]; then
        log "Cloning dotfiles repository to a temporary directory..."
        TEMP_DIR=$(mktemp -d)
        git clone "$REPO_URL" "$TEMP_DIR"
        
        log "Checking for differing files in $DOTFILES_DIR..."
        find "$TEMP_DIR" -type f -not -path "*/.git/*" | while read -r new_file; do
            # Get the relative path of the file
            relative_path="${new_file#$TEMP_DIR/}"
            existing_file="$DOTFILES_DIR/$relative_path"
            if [ -f "$existing_file" ]; then
                # Compare file contents
                if cmp -s "$existing_file" "$new_file"; then
                    log "$relative_path is identical, skipping..."
                else
                    log "Renaming $existing_file to $existing_file.bak"
                    mv "$existing_file" "$existing_file.bak"
                    mkdir -p "$(dirname "$existing_file")"
                    cp "$new_file" "$existing_file"
                    log "Replaced $relative_path with new version"
                fi
            else
                log "Copying new file $relative_path to $DOTFILES_DIR"
                mkdir -p "$(dirname "$existing_file")"
                cp "$new_file" "$existing_file"
            fi
        done
        
        log "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
        cd "$DOTFILES_DIR"
    else
        error "Operation aborted by user. Please remove or rename $DOTFILES_DIR manually to proceed."
        exit 1
    fi
else
    log "Cloning dotfiles repository..."
    git clone "$REPO_URL" "$DOTFILES_DIR"
    cd "$DOTFILES_DIR"
fi

# ----------------------
# Helper functions
# ----------------------
install_package() {
    local pkg="$1"

    # Skip if already installed
    if pacman -Qs "$pkg" &> /dev/null; then
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

uninstall_package() {
    local pkg="$1"

    if pacman -Qs "$pkg" &> /dev/null; then
        log "Uninstalling $pkg with pacman..."
        if sudo pacman -Rns --noconfirm "$pkg"; then
            log "$pkg uninstalled via pacman"
            return
        fi
    fi

    if [ -n "$AUR_HELPER" ]; then
        log "Trying to uninstall $pkg via $AUR_HELPER..."
        if "$AUR_HELPER" -Rns --noconfirm "$pkg"; then
            log "$pkg uninstalled via $AUR_HELPER"
            return
        fi
    fi

    error "Failed to uninstall $pkg"
}

# ----------------------
# Uninstall packages
# ----------------------
if [ -f "$UNINSTALL_PACKAGES_FILE" ]; then
    # Read packages, skip comments and empty lines
    mapfile -t UNINSTALL_PACKAGES < <(grep -vE '^\s*#|^\s*$' "$UNINSTALL_PACKAGES_FILE")

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

mapfile -t INSTALL_PACKAGES < <(grep -vE '^\s*#|^\s*$' "$INSTALL_PACKAGES_FILE")

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
stow hyprland
stow kitty
stow starship
stow screenlayout
stow waybar

# Automated option (iterate over each folder in dotfiles)
# Uncomment to test
# for dir in */ ; do
#     stow "${dir%/}"
# done

log "Dotfiles installation completed successfully!"