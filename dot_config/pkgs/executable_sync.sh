#!/usr/bin/env bash
set -euo pipefail

read -rp "Is this the laptop or the pc? [l/p]: " which
case "$which" in
  l|L)
    echo "Running in laptop mode"

    # Generate laptop's own lists
    pacman -Qqen > lpacman.pkgs
    pacman -Qqm  > laur.pkgs

    # Files from PC must already exist: pacman.pkgs, aur.pkgs
    if [[ ! -f pacman.pkgs || ! -f aur.pkgs ]]; then
      echo "Error: pacman.pkgs and aur.pkgs from PC must be present in this directory."
      exit 1
    fi

    # Sort all files (comm requires sorted input)
    sort pacman.pkgs -o pacman.pkgs
    sort aur.pkgs    -o aur.pkgs
    sort lpacman.pkgs -o lpacman.pkgs
    sort laur.pkgs    -o laur.pkgs

    # Packages PC has that laptop does NOT (what you might want to install on laptop)
    comm -23 pacman.pkgs lpacman.pkgs > pc_only_pacman.tmp
    comm -23 aur.pkgs    laur.pkgs    > pc_only_aur.tmp

    # Packages laptop has that PC does NOT (extra stuff on laptop)
    comm -13 pacman.pkgs lpacman.pkgs > laptop_extra_pacman.tmp
    comm -13 aur.pkgs    laur.pkgs    > laptop_extra_aur.tmp

    echo "Generated:"
    echo "  lpacman.pkgs (laptop pacman list)"
    echo "  laur.pkgs    (laptop AUR list)"
    echo "  pc_only_pacman.tmp     (PC-only pacman packages)"
    echo "  pc_only_aur.tmp        (PC-only AUR packages)"
    echo "  laptop_extra_pacman.tmp (laptop-only pacman packages)"
    echo "  laptop_extra_aur.tmp    (laptop-only AUR packages)"
    ;;

  p|P)
    echo "Running in pc mode"

    # Generate PC's own lists
    pacman -Qqen > pacman.pkgs
    pacman -Qqm  > aur.pkgs

    # Files from laptop must already exist: lpacman.pkgs, laur.pkgs
    if [[ ! -f lpacman.pkgs || ! -f laur.pkgs ]]; then
      echo "Error: lpacman.pkgs and laur.pkgs from laptop must be present in this directory."
      exit 1
    fi

    # Sort all files
    sort pacman.pkgs -o pacman.pkgs
    sort aur.pkgs    -o aur.pkgs
    sort lpacman.pkgs -o lpacman.pkgs
    sort laur.pkgs    -o laur.pkgs

    # Packages PC has that laptop does NOT (extra stuff on PC)
    comm -23 pacman.pkgs lpacman.pkgs > pc_extra_pacman.tmp
    comm -23 aur.pkgs    laur.pkgs    > pc_extra_aur.tmp

    # Packages laptop has that PC does NOT (what you might want to install on PC)
    comm -13 pacman.pkgs lpacman.pkgs > laptop_only_pacman.tmp
    comm -13 aur.pkgs    laur.pkgs    > laptop_only_aur.tmp

    echo "Generated:"
    echo "  pacman.pkgs (PC pacman list)"
    echo "  aur.pkgs    (PC AUR list)"
    echo "  pc_extra_pacman.tmp      (PC-only pacman packages)"
    echo "  pc_extra_aur.tmp         (PC-only AUR packages)"
    echo "  laptop_only_pacman.tmp   (laptop-only pacman packages)"
    echo "  laptop_only_aur.tmp      (laptop-only AUR packages)"
    ;;

  *)
    echo "Please answer 'l' for laptop or 'p' for pc."
    exit 1
    ;;
esac

