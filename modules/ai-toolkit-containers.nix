{ lib, pkgs, ... }:

let
  inherit (lib) mkEnableOption mkIf mkOption types mkMerge mapAttrsToList optionalString;

  cfg = config.services.aiToolkitContainers;

  mkStageScript = name: c: pkgs.writeShellScript "stage-ai-toolkit-${name}" ''
    set -euo pipefail

    mkdir -p "${c.stateDir}"

    if [ ! -e "${c.workingDir}/README.md" ]; then
      echo "[ai-toolkit:${name}] seeding ${c.workingDir} from ${c.aiToolkitSrc}"
      mkdir -p "${c.workingDir}"
      cp -R --no-preserve=mode,ownership "${c.aiToolkitSrc}/." "${c.workingDir}/"
    fi

    if [ "${if c.refreshOnRebuild then "1" else "0"}" = "1" ]; then
      echo "[ai-toolkit:${name}] refreshOnRebuild enabled; syncing upstream"
      if command -v ${pkgs.rsync}/bin/rsync >/dev/null 2>&1; then
        ${pkgs.rsync}/bin/rsync -a --delete \
          --exclude '.git/' \
          "${c.aiToolkitSrc}/" "${c.workingDir}/"
      fi
    fi
  '';

  mkSvc = name: c: {
    systemd.services."ai-toolkit-${name}" = {
      description = "AI Toolkit (${name})";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = c.user;
        WorkingDirectory = c.workingDir;
        Restart = "on-failure";
        RestartSec = 3;
        EnvironmentFile = lib.mkIf (c.environmentFile != null) c.environmentFile;

        ExecStart = pkgs.writeShellScript "start-ai-toolkit-${name}" ''
          set -euo pipefail

          ${mkStageScript name c}

          export CUDA_HOME="${c.cudaHome}"
          export LD_LIBRARY_PATH="${c.openglLibPath}:$LD_LIBRARY_PATH"

          eval "$(${pkgs.micromamba}/bin/micromamba shell hook -s bash)"
          micromamba activate "${c.mambaEnv}"

          ${optionalString (c.preStart != "") c.preStart}

          exec ${lib.escapeShellArgs c.command}
        '';
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf c.openFirewall [ c.port ];
  };

in {
  options.services.aiToolkitContainers = {
    enable = mkEnableOption "Enable AI toolkit instances";

    defaults = {
      user = mkOption { type = types.str; default = "jsampson"; };
      cudaHome = mkOption { type = types.str; default = "/run/opengl-driver"; };
      openglLibPath = mkOption { type = types.str; default = "/run/opengl-driver/lib"; };

      aiToolkitSrc = mkOption { type = types.path; };
      baseStateDir = mkOption { type = types.str; default = "/var/lib/ai-toolkit"; };

      port = mkOption { type = types.int; default = 7860; };
      openFirewall = mkOption { type = types.bool; default = false; };

      environmentFile = mkOption { type = types.nullOr types.str; default = null; };
      preStart = mkOption { type = types.str; default = ""; };
    };

    instances = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkEnableOption "Enable this AI toolkit instance";

          user = mkOption { type = types.str; default = cfg.defaults.user; };
          mambaEnv = mkOption { type = types.str; default = "ai-toolkit"; };

          stateDir = mkOption { type = types.str; default = "${cfg.defaults.baseStateDir}/${name}"; };

          aiToolkitSrc = mkOption { type = types.path; default = cfg.defaults.aiToolkitSrc; };

          workingDir = mkOption {
            type = types.str;
            default = "${config.services.aiToolkitContainers.instances.${name}.stateDir}/ai-toolkit";
          };

          refreshOnRebuild = mkOption { type = types.bool; default = false; };

          cudaHome = mkOption { type = types.str; default = cfg.defaults.cudaHome; };
          openglLibPath = mkOption { type = types.str; default = cfg.defaults.openglLibPath; };

          port = mkOption { type = types.int; default = cfg.defaults.port; };
          openFirewall = mkOption { type = types.bool; default = cfg.defaults.openFirewall; };

          command = mkOption {
            type = types.listOf types.str;
            default = [ "python" "main.py" ];
          };

          environmentFile = mkOption { type = types.nullOr types.str; default = cfg.defaults.environmentFile; };
          preStart = mkOption { type = types.str; default = cfg.defaults.preStart; };
        };
      }));
      default = { };
    };
  };

  config = mkIf cfg.enable (mkMerge (
    mapAttrsToList (name: c: mkIf c.enable (mkSvc name c)) cfg.instances
  ));
}

