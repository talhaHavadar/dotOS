# Put packages from `nix profile install` on PATH for login shells
case ":${PATH}:" in
    *":${HOME}/.nix-profile/bin:"*) ;;
    *) PATH="${HOME}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH}" ;;
esac
export PATH
