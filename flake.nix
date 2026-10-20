{
  description = "NixOS system nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Cursor's launcher needs nixGL. A flake input is locked in flake.lock.
    # builtins.fetchTarball of GitHub main is rejected in pure evaluation.
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixgl, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        ./lampp.nix
        {
          nixpkgs.overlays = [
            nixgl.overlays.default
            # qtile 0.37 calls wlr_xcursor_image_get_buffer, which is wlroots 0.20.
            # nixpkgs still passes wlroots_0_19 into the qtile build.
            (final: prev: {
              pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
                (_pyFinal: pyPrev: {
                  qtile = pyPrev.qtile.override {
                    wlroots = final.wlroots_0_20;
                  };
                })
              ];
            })
	    (final: prev: {                                                     
                    code-cursor = (import nixpkgs-unstable {                        
                      system = final.stdenv.hostPlatform.system;                  
                      config.allowUnfree = true;                                  
                  }).code-cursor;                                                 
            })    
          ];
        }
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          # Move an unmanaged file aside instead of aborting activation.
          home-manager.backupFileExtension = "hmbak";
          home-manager.users.nathaniel = ./home.nix;
        }
      ];
    };
  };
}
