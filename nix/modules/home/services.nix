{
  pkgs,
  lib,
  username,
  settings,
  isDarwin,
  isLinux,
  ...
}:

{
  # Linux systemd user services
  systemd.user.services = lib.optionalAttrs isLinux {
    atuin = {
      Unit = {
        Description = "Atuin Shell History Daemon";
        After = [ "default.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.atuin}/bin/atuin daemon start";
        ExecStop = "${pkgs.atuin}/bin/atuin daemon stop";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    gopls = {
      Unit = {
        Description = "Gopls Daemon Server";
        After = [ "network.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.gopls}/bin/gopls -listen=${settings.services.gopls.host}:${toString settings.services.gopls.port} -logfile=${settings.services.gopls.logfile}";
        Restart = "on-failure";
        RestartSec = "5s";
        StandardOutput = "syslog";
        StandardError = "syslog";
        SyslogIdentifier = "gopls";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # Mirrors systemd/user/kanshi.service (which hardcodes /usr/bin/kanshi, absent
    # on Nix hosts); arch/sway.conf no longer execs kanshi itself.
    kanshi = {
      Unit = {
        Description = "Dynamic display configuration daemon (kanshi)";
        Documentation = [ "man:kanshi(1)" ];
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.kanshi}/bin/kanshi";
        ExecReload = "${pkgs.kanshi}/bin/kanshictl reload";
        Restart = "always";
        RestartSec = "3s";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };

  # Mirrors systemd/user/sway-session.target; started by arch/sway.conf's autostart.
  systemd.user.targets = lib.optionalAttrs isLinux {
    sway-session = {
      Unit = {
        Description = "sway compositor session";
        Documentation = [ "man:systemd.special(7)" ];
        BindsTo = [ "graphical-session.target" ];
        Wants = [ "graphical-session-pre.target" ];
        After = [ "graphical-session-pre.target" ];
      };
    };
  };

  # macOS launchd agents, mirroring the Linux systemd user services above.
  launchd.agents = lib.optionalAttrs isDarwin {
    # zsh/30-atuin.zsh actively depends on this daemon: it checks
    # `atuin daemon status`, restarts it on version bumps, and its own
    # comments say the daemon being unreachable makes atuin "fall back to
    # direct SQLite writes, breaking real-time sync" — this was previously
    # Linux-only (systemd unit above), leaving darwin silently degraded.
    # `atuin daemon start` is the same long-running foreground process either
    # unit type expects (systemd's Type=simple requires it, and it is in fact
    # what that unit already runs), so this only needs a plain RunAtLoad +
    # KeepAlive agent — no PATH override like gopls needs, since atuin doesn't
    # shell out to another binary.
    atuin = {
      enable = true;
      config = {
        Label = "com.${username}.atuin-daemon";
        ProgramArguments = [
          "${pkgs.atuin}/bin/atuin"
          "daemon"
          "start"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
      };
    };

    gopls = {
      enable = true;
      config = {
        Label = "com.${username}.gopls-daemon";
        ProgramArguments = [
          "${pkgs.gopls}/bin/gopls"
          "-listen=${settings.services.gopls.host}:${toString settings.services.gopls.port}"
          "-logfile=${settings.services.gopls.logfile}"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        EnvironmentVariables = {
          # launchd agents do not inherit the shell PATH, so the Go toolchain has
          # to be named explicitly — gopls shells out to `go` for module and
          # package resolution and is close to useless without it.
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:${pkgs.go}/bin:${pkgs.gopls}/bin";
        };
      };
    };
  };
}
