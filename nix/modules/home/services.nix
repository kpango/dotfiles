{ pkgs, lib, username, settings, isDarwin, isLinux, ... }:

{
  # Linux systemd service for gopls
  systemd.user.services = lib.optionalAttrs isLinux {
    gopls = {
      Unit = {
        Description = "Gopls Daemon Server";
        After = [ "network.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.gopls}/bin/gopls -listen=:${toString settings.services.gopls.port} -logfile=${settings.services.gopls.logfile}";
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
  };

  # macOS launchd agent for gopls
  launchd.agents = lib.optionalAttrs isDarwin {
    gopls = {
      enable = true;
      config = {
        Label = "com.${username}.gopls-daemon";
        ProgramArguments = [
          "${pkgs.gopls}/bin/gopls"
          "-listen=:${toString settings.services.gopls.port}"
          "-logfile=${settings.services.gopls.logfile}"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        EnvironmentVariables = {
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:${pkgs.gopls}/bin";
        };
      };
    };
  };
}
