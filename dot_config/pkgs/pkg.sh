#!/bin/zsh
# pkg - package list manager
# Manages declarative package lists synced via chezmoi.
# Does NOT auto-install anything. You review and run commands yourself.
#
# Usage:
#   pkg add <package> [--<machine>]   Add a package to a list
#   pkg rm  <package> [--<machine>]   Remove a package from list(s)
#   pkg ls  [--all|--<machine>]       List managed packages
#   pkg diff                          Show what needs installing/removing
#   pkg sync                          Generate install commands to review & run

PKGDIR="$HOME/.config/pkgs"

# Get current machine name from chezmoi data
_pkg_machine() {
    chezmoi data -f json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('machine',''))" 2>/dev/null
}

# Check if package is in official repos
_pkg_is_official() {
    pacman -Si "$1" &>/dev/null
}

# Add a package to a list file (sorted, deduped)
_pkg_list_add() {
    local pkg="$1" file="$2"
    if ! grep -qx "$pkg" "$file" 2>/dev/null; then
        echo "$pkg" >> "$file"
        sort -uo "$file" "$file"
    fi
}

# Remove a package from a list file
_pkg_list_rm() {
    local pkg="$1" file="$2"
    if [[ -f "$file" ]]; then
        sed -i "/^${pkg}$/d" "$file"
    fi
}

# Re-add changed files to chezmoi source
_pkg_readd() {
    chezmoi re-add "$PKGDIR/" 2>/dev/null
}

pkg() {
    local action="$1"
    shift || { echo "Usage: pkg <add|rm|ls|diff|sync> [args]"; return 1; }

    case "$action" in
        add)
            local pkg="" target_machine=""
            for arg in "$@"; do
                if [[ "$arg" == --* ]]; then
                    target_machine="${arg#--}"
                else
                    pkg="$arg"
                fi
            done

            if [[ -z "$pkg" ]]; then
                echo "Usage: pkg add <package> [--<machine>]"
                return 1
            fi

            # Determine if official or AUR
            local prefix
            if _pkg_is_official "$pkg"; then
                prefix="pacman"
            else
                prefix="aur"
            fi

            local list_suffix="${target_machine:-common}"
            local list_file="$PKGDIR/${prefix}-${list_suffix}.pkgs"

            _pkg_list_add "$pkg" "$list_file"
            echo "Added '$pkg' to $(basename "$list_file")"
            echo "Run: $([ "$prefix" = "pacman" ] && echo "sudo pacman -S $pkg" || echo "paru -S $pkg")"

            _pkg_readd
            ;;

        rm)
            local pkg="" target_machine=""
            for arg in "$@"; do
                if [[ "$arg" == --* ]]; then
                    target_machine="${arg#--}"
                else
                    pkg="$arg"
                fi
            done

            if [[ -z "$pkg" ]]; then
                echo "Usage: pkg rm <package> [--<machine>]"
                return 1
            fi

            if [[ -n "$target_machine" ]]; then
                for prefix in pacman aur; do
                    _pkg_list_rm "$pkg" "$PKGDIR/${prefix}-${target_machine}.pkgs"
                done
                echo "Removed '$pkg' from $target_machine lists"
            else
                for f in "$PKGDIR"/pacman-*.pkgs "$PKGDIR"/aur-*.pkgs; do
                    _pkg_list_rm "$pkg" "$f"
                done
                echo "Removed '$pkg' from all lists"
            fi

            echo "Run: sudo pacman -Rns $pkg"
            _pkg_readd
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

            # Build target list for this machine
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

            echo "# Review these commands, then copy-paste to run:"
            echo ""
            if [[ -n "$pacman_missing" ]]; then
                echo "sudo pacman -S --needed $(echo $pacman_missing | tr '\n' ' ')"
                echo ""
            else
                echo "# All pacman packages installed"
            fi
            if [[ -n "$aur_missing" ]]; then
                echo "paru -S --needed $(echo $aur_missing | tr '\n' ' ')"
                echo ""
            else
                echo "# All AUR packages installed"
            fi
            ;;

        *)
            echo "Usage: pkg <add|rm|ls|diff|sync> [args]"
            echo ""
            echo "  add <pkg> [--machine]   Add package to a list (doesn't install)"
            echo "  rm  <pkg> [--machine]   Remove package from list(s) (doesn't uninstall)"
            echo "  ls  [--all|--machine]   Show managed package lists"
            echo "  diff                    Show what's missing or extra"
            echo "  sync                    Generate install commands to review & run"
            return 1
            ;;
    esac
}
