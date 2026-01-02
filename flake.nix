{
  description = "BinaryBlaze AI Toolkit services (flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ai-toolkit = {
      url = "github:ostris/ai-toolkit";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ai-toolkit, ... }:
  let
    systems = [ "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in
  {
    nixosModules.default = { lib, pkgs, ... }: {
      imports = [ ./modules/ai-toolkit-containers.nix ];

      services.aiToolkitContainers.defaults = {
        aiToolkitSrc = ai-toolkit;
        baseStateDir = "/var/lib/ai-toolkit";
      };
    };

    packages = forAllSystems (system: {
      upstream-src = ai-toolkit;
    });
  };
}

