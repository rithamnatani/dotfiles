#!/bin/zsh
# pkg - package list manager
# Manages declarative package lists synced via chezmoi.
# Shows you the command, you type it to confirm, then it runs.
#
# Usage:
#   pkg add <package...> [--<machine>]   Install + add to list
#   pkg rm  <package...> [--<machine>]   Remove + remove from list
#   pkg ls  [--all|--<machine>]          List managed packages
#   pkg diff                             Show what's missing or extra
#   pkg sync                             Install missing packages
#   pkg update                           Reconcile lists with installed state
#   pkg move <package> <destination>     Move package between lists

PKGDIR="$HOME/.config/pkgs"

_pkg_machine() {
    chezmoi data -f json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('machine',''))" 2>/dev/null
}

_pkg_is_official() {
    pacman -Si "$1" &>/dev/null
}

_pkg_list_add() {
    local pkg="$1" file="$2"
    if ! grep -qx "$pkg" "$file" 2>/dev/null; then
        echo "$pkg" >> "$file"
        sort -uo "$file" "$file"
    fi
}

_pkg_list_rm() {
    local pkg="$1" file="$2"
    if [[ -f "$file" ]]; then
        sed -i "/^${pkg}$/d" "$file"
    fi
}

_pkg_readd() {
    chezmoi re-add "$PKGDIR/" 2>/dev/null
}

pkg() {
    local action="$1"
    shift || { echo "Usage: pkg <add|rm|ls|diff|sync|update|move> [args]"; return 1; }

    case "$action" in
        add)
            local pkgs=() target_machine=""
            for arg in "$@"; do
                if [[ "$arg" == --* ]]; then
                    target_machine="${arg#--}"
                else
                    pkgs+=("$arg")
                fi
            done

            if [[ ${#pkgs[@]} -eq 0 ]]; then
                echo "Usage: pkg add <package...> [--<machine>]"
                return 1
            fi

            local current_machine
            current_machine=$(_pkg_machine)
            local list_suffix="${target_machine:-common}"

            # Split into official and AUR
            local official=() aur=()
            for p in "${pkgs[@]}"; do
                if _pkg_is_official "$p"; then
                    official+=("$p")
                else
                    aur+=("$p")
                fi
            done

            # If targeting a different machine, just add to list (can't install)
            if [[ -n "$target_machine" && "$target_machine" != "$current_machine" ]]; then
                for p in "${pkgs[@]}"; do
                    local prefix=$(_pkg_is_official "$p" && echo "pacman" || echo "aur")
                    _pkg_list_add "$p" "$PKGDIR/${prefix}-${list_suffix}.pkgs"
                done
                echo "Added to ${list_suffix} lists (not on this machine, skipping install)"
                _pkg_readd
                return 0
            fi

            # Handle official packages
            if [[ ${#official[@]} -gt 0 ]]; then
                local cmd="sudo pacman -S ${official[*]}"
                echo ""
                echo "  Packages (official):"
                for p in "${official[@]}"; do
                    echo "    $p"
                done
                echo ""
                echo "  List: pacman-${list_suffix}.pkgs"
                echo ""
                echo -n "Type 'pacman -S' to confirm: "
                read -r confirm
                if [[ "$confirm" == "pacman -S" ]]; then
                    sudo pacman -S "${official[@]}"
                    if [[ $? -eq 0 ]]; then
                        for p in "${official[@]}"; do
                            _pkg_list_add "$p" "$PKGDIR/pacman-${list_suffix}.pkgs"
                        done
                        _pkg_readd
                        echo "Added to pacman-${list_suffix}.pkgs"
                    else
                        echo "Install failed, not updating list"
                        return 1
                    fi
                else
                    echo "Aborted"
                    return 1
                fi
            fi

            # Handle AUR packages
            if [[ ${#aur[@]} -gt 0 ]]; then
                echo ""
                echo "  Packages (AUR):"
                for p in "${aur[@]}"; do
                    echo "    $p"
                done
                echo ""
                echo "  List: aur-${list_suffix}.pkgs"
                echo ""
                echo -n "Type 'paru -S' to confirm: "
                read -r confirm
                if [[ "$confirm" == "paru -S" ]]; then
                    paru -S "${aur[@]}"
                    if [[ $? -eq 0 ]]; then
                        for p in "${aur[@]}"; do
                            _pkg_list_add "$p" "$PKGDIR/aur-${list_suffix}.pkgs"
                        done
                        _pkg_readd
                        echo "Added to aur-${list_suffix}.pkgs"
                    else
                        echo "Install failed, not updating list"
                        return 1
                    fi
                else
                    echo "Aborted"
                    return 1
                fi
            fi
            ;;

        rm)
            local pkgs=() target_machine=""
            for arg in "$@"; do
                if [[ "$arg" == --* ]]; then
                    target_machine="${arg#--}"
                else
                    pkgs+=("$arg")
                fi
            done

            if [[ ${#pkgs[@]} -eq 0 ]]; then
                echo "Usage: pkg rm <package...> [--<machine>]"
                return 1
            fi

            # If targeting a different machine, just remove from that list
            local current_machine
            current_machine=$(_pkg_machine)
            if [[ -n "$target_machine" && "$target_machine" != "$current_machine" ]]; then
                for p in "${pkgs[@]}"; do
                    for prefix in pacman aur; do
                        _pkg_list_rm "$p" "$PKGDIR/${prefix}-${target_machine}.pkgs"
                    done
                done
                echo "Removed from ${target_machine} lists"
                _pkg_readd
                return 0
            fi

            echo ""
            echo "  Packages to remove:"
            for p in "${pkgs[@]}"; do
                echo "    $p"
            done
            if [[ -n "$target_machine" ]]; then
                echo "  From: ${target_machine} lists only"
            else
                echo "  From: all lists"
            fi
            echo ""
            echo -n "Type 'pacman -Rns' to confirm: "
            read -r confirm
            if [[ "$confirm" == "pacman -Rns" ]]; then
                sudo pacman -Rns "${pkgs[@]}"
                if [[ $? -eq 0 ]]; then
                    for p in "${pkgs[@]}"; do
                        if [[ -n "$target_machine" ]]; then
                            for prefix in pacman aur; do
                                _pkg_list_rm "$p" "$PKGDIR/${prefix}-${target_machine}.pkgs"
                            done
                        else
                            for f in "$PKGDIR"/pacman-*.pkgs "$PKGDIR"/aur-*.pkgs; do
                                _pkg_list_rm "$p" "$f"
                            done
                        fi
                    done
                    _pkg_readd
                    echo "Removed from lists"
                else
                    echo "Removal failed, not updating lists"
                    return 1
                fi
            else
                echo "Aborted"
                return 1
            fi
            ;;

        ls)
            local filter="${1:---all}"
            case "$filter" in
                --all)
                    for f in "$PKGDIR"/*.pkgs; do
                        [[ -f "$f" ]] || continue
                        echo "=== $(basename "$f") ==="
                        cat "$f"
                        echo ""
                    done
                    ;;
                --*)
                    local machine="${filter#--}"
                    for f in "$PKGDIR"/*-${machine}.pkgs; do
                        [[ -f "$f" ]] || continue
                        echo "=== $(basename "$f") ==="
                        cat "$f"
                        echo ""
                    done
                    ;;
            esac
            ;;

        diff)
            local current_machine
            current_machine=$(_pkg_machine)
            if [[ -z "$current_machine" ]]; then
                echo "Error: machine not set. Run: chezmoi init"
                return 1
            fi

            local target
            target=$(cat "$PKGDIR"/pacman-common.pkgs "$PKGDIR"/pacman-${current_machine}.pkgs \
                         "$PKGDIR"/aur-common.pkgs "$PKGDIR"/aur-${current_machine}.pkgs 2>/dev/null \
                     | grep -v '^#' | grep -v '^$' | sort -u)
            local installed
            installed=$(pacman -Qqe | sort -u)

            local missing=$(comm -23 <(echo "$target") <(echo "$installed"))
            local extra=$(comm -13 <(echo "$target") <(comm -12 <(echo "$installed") <(cat "$PKGDIR"/*.pkgs 2>/dev/null | grep -v '^#' | grep -v '^$' | sort -u)))

            if [[ -n "$missing" ]]; then
                echo "=== Missing (in lists but not installed) ==="
                echo "$missing"
                echo ""
            fi
            if [[ -n "$extra" ]]; then
                echo "=== Extra (installed but not in $current_machine lists) ==="
                echo "$extra"
                echo ""
            fi
            if [[ -z "$missing" && -z "$extra" ]]; then
                echo "Everything in sync!"
            fi
            ;;

        sync)
            local current_machine
            current_machine=$(_pkg_machine)
            if [[ -z "$current_machine" ]]; then
                echo "Error: machine not set. Run: chezmoi init"
                return 1
            fi

            local pacman_target
            pacman_target=$(cat "$PKGDIR"/pacman-common.pkgs "$PKGDIR"/pacman-${current_machine}.pkgs 2>/dev/null \
                            | grep -v '^#' | grep -v '^$' | sort -u)
            local aur_target
            aur_target=$(cat "$PKGDIR"/aur-common.pkgs "$PKGDIR"/aur-${current_machine}.pkgs 2>/dev/null \
                         | grep -v '^#' | grep -v '^$' | sort -u)
            local installed
            installed=$(pacman -Qqe | sort -u)

            local pacman_missing=$(comm -23 <(echo "$pacman_target") <(echo "$installed"))
            local aur_missing=$(comm -23 <(echo "$aur_target") <(echo "$installed"))

            if [[ -z "$pacman_missing" && -z "$aur_missing" ]]; then
                echo "Everything in sync!"
                return 0
            fi

            if [[ -n "$pacman_missing" ]]; then
                echo ""
                echo "  Missing official packages:"
                echo "$pacman_missing" | sed 's/^/    /'
                echo ""
                echo -n "Type 'pacman -S' to install, or anything else to skip: "
                read -r confirm
                if [[ "$confirm" == "pacman -S" ]]; then
                    sudo pacman -S --needed $(echo "$pacman_missing")
                fi
            fi

            if [[ -n "$aur_missing" ]]; then
                echo ""
                echo "  Missing AUR packages:"
                echo "$aur_missing" | sed 's/^/    /'
                echo ""
                echo -n "Type 'paru -S' to install, or anything else to skip: "
                read -r confirm
                if [[ "$confirm" == "paru -S" ]]; then
                    paru -S --needed $(echo "$aur_missing")
                fi
            fi
            ;;

        update)
            local current_machine
            current_machine=$(_pkg_machine)
            if [[ -z "$current_machine" ]]; then
                echo "Error: machine not set. Run: chezmoi init"
                return 1
            fi

            # All packages in ANY list
            local all_listed
            all_listed=$(cat "$PKGDIR"/*.pkgs 2>/dev/null | grep -v '^#' | grep -v '^$' | sort -u)

            # All packages that should be on this machine
            local target
            target=$(cat "$PKGDIR"/pacman-common.pkgs "$PKGDIR"/pacman-${current_machine}.pkgs \
                         "$PKGDIR"/aur-common.pkgs "$PKGDIR"/aur-${current_machine}.pkgs 2>/dev/null \
                     | grep -v '^#' | grep -v '^$' | sort -u)

            local installed
            installed=$(pacman -Qqe | sort -u)

            # Installed but not in any list
            local unlisted
            unlisted=$(comm -23 <(echo "$installed") <(echo "$all_listed"))

            # In this machine's lists but not installed
            local removed
            removed=$(comm -23 <(echo "$target") <(echo "$installed"))

            if [[ -z "$unlisted" && -z "$removed" ]]; then
                echo "Lists are up to date!"
                return 0
            fi

            if [[ -n "$unlisted" ]]; then
                echo ""
                echo "=== Installed but not in any list ==="
                echo "$unlisted" | sed 's/^/  /'
                echo ""
                echo -n "Add these to ${current_machine} lists? [y/N]: "
                read -r confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    for p in $(echo "$unlisted"); do
                        if _pkg_is_official "$p"; then
                            _pkg_list_add "$p" "$PKGDIR/pacman-${current_machine}.pkgs"
                        else
                            _pkg_list_add "$p" "$PKGDIR/aur-${current_machine}.pkgs"
                        fi
                    done
                    echo "Added to ${current_machine} lists"
                fi
            fi

            if [[ -n "$removed" ]]; then
                echo ""
                echo "=== In lists but not installed ==="
                echo "$removed" | sed 's/^/  /'
                echo ""
                echo -n "Remove these from lists? [y/N]: "
                read -r confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    for p in $(echo "$removed"); do
                        for f in "$PKGDIR"/pacman-*.pkgs "$PKGDIR"/aur-*.pkgs; do
                            _pkg_list_rm "$p" "$f"
                        done
                    done
                    echo "Removed from lists"
                fi
            fi

            _pkg_readd
            ;;

        move)
            local pkg="$1" destination="$2"
            if [[ -z "$pkg" || -z "$destination" ]]; then
                echo "Usage: pkg move <package> <destination>"
                echo "  destination: common, desktop, zephyrus, etc."
                return 1
            fi

            # Find and remove from current list(s)
            local found=0 prefix=""
            for f in "$PKGDIR"/*.pkgs; do
                [[ -f "$f" ]] || continue
                if grep -qx "$pkg" "$f"; then
                    local bn=$(basename "$f")
                    prefix="${bn%%-*}"
                    _pkg_list_rm "$pkg" "$f"
                    echo "Removed from $bn"
                    found=1
                fi
            done

            if [[ $found -eq 0 ]]; then
                echo "Package '$pkg' not found in any list"
                return 1
            fi

            local dest_file="${prefix}-${destination}.pkgs"
            _pkg_list_add "$pkg" "$PKGDIR/$dest_file"
            echo "Moved to $dest_file"

            _pkg_readd
            ;;

        *)
            echo "Usage: pkg <add|rm|ls|diff|sync|update|move>"
            echo ""
            echo "  add    <pkg...> [--machine]    Install + add to list"
            echo "  rm     <pkg...> [--machine]    Remove + remove from list"
            echo "  ls     [--all|--machine]       Show managed package lists"
            echo "  diff                           Show what's missing or extra"
            echo "  sync                           Install missing packages"
            echo "  update                         Reconcile lists with installed state"
            echo "  move   <pkg> <destination>     Move package between lists"
            return 1
            ;;
    esac
}
