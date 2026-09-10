{
  lib,
  settings,
  username,
  dotfilesPath,
  ...
}:

let
  identity =
    settings.git.identities.${username} or {
      name = settings.fullName;
      inherit (settings) email;
      signingKey = null;
    };
  hasSigningKey = (identity.signingKey or null) != null;
in
{
  programs.git = {
    enable = true;
    # core.excludesfile is deliberately not set here: dotfiles/gitconfig already
    # points it at ~/.gitignore, which modules/home/dotfiles/shared.nix installs,
    # and the include below would override this module's value anyway.
    includes = [
      { path = "${dotfilesPath}/gitconfig"; }
    ];
  };

  # home-manager appends `includes` to git/config with mkAfter (== mkOrder 1500),
  # so dotfiles/gitconfig is the last thing git reads and its [user] section wins
  # over programs.git.settings. Re-assert the identity at a later order so the
  # per-account values in settings.git.identities are the ones that apply.
  xdg.configFile."git/config".text = lib.mkOrder 1600 (
    lib.generators.toGitINI {
      user = {
        inherit (identity) name email;
      }
      // lib.optionalAttrs hasSigningKey { signingkey = identity.signingKey; };

      # gitconfig turns both of these on unconditionally; without the key in the
      # local keyring that makes every commit and tag fail to sign.
      commit.gpgsign = hasSigningKey;
      tag.gpgsign = hasSigningKey;
    }
  );
}
