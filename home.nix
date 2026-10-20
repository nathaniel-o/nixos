# User profile for nathaniel.
# Personal programs only. The account, Plasma, and services stay in configuration.nix.
# Apply with: sudo nixos-rebuild switch --flake /etc/nixos#nixos
{ pkgs, lib, ... }:
{
  home.username = "nathaniel";
  home.homeDirectory = "/home/nathaniel";
  home.stateVersion = "26.05";

  programs.bash = {
    enable = true;
    # env.sh is what ~/.bashrc used to source. It adds the LAMPP bins,
    # then sources aliases.sh, which adds Desktop/the_Study to PATH.
    bashrcExtra = ''
      source /home/nathaniel/Desktop/the_Study/env.sh
    '';
  };

 
 
	programs.gh = {
	  enable = true;
	  settings = {
	    git_protocol = "ssh";
	    aliases = {
	      co = "pr checkout";
	      pv = "pr view";
	    };
	  };
	  gitCredentialHelper = {
	    enable = true;
	    hosts = [ "https://github.com" ];
	  };
	  # Install extensions from nixpkgs
	  extensions = [ pkgs.gh-s ];
	};   
    
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      {
        "text/html" = [ "brave-browser.desktop" ];
        "x-scheme-handler/http" = [ "brave-browser.desktop" ];
        "x-scheme-handler/https" = [ "brave-browser.desktop" ];
      }
      // lib.genAttrs [
        "image/avif"
        "image/gif"
        "image/heif"
        "image/jpeg"
        "image/jxl"
        "image/png"
        "image/bmp"
        "image/x-eps"
        "image/x-icns"
        "image/x-ico"
        "image/x-portable-bitmap"
        "image/x-portable-graymap"
        "image/x-portable-pixmap"
        "image/x-xbitmap"
        "image/x-xpixmap"
        "image/tiff"
        "image/x-psd"
        "image/x-webp"
        "image/webp"
        "image/x-tga"
        "image/x-xcf"
        "image/openraster"
        "image/svg+xml"
        "image/svg+xml-compressed"
      ] (_: [ "org.kde.gwenview.desktop" ]);
  };

 

  home.packages = with pkgs; [
    vim
    wget
    git
    rofi
    brave
    neovim
    networkmanagerapplet
    keepassxc
    firefly-iii
    microsoft-edge
    kdePackages.kate
    freecad
    swift
    unzip
    chromium
    htop
    obsidian
    libreoffice
    (writeShellApplication {
      name = "phone-screen";
      runtimeInputs = [
        wayvnc
        wlr-randr
        android-tools
        iproute2
        python3
        openssl
      ];
      text = builtins.readFile ./phone-screen.sh;
    })
    (writeShellApplication {
      name = "cursor";
      text = ''
        # nixGLDefault reads /proc and builtins.currentTime, which flakes reject.
        # This machine is Intel, so the pure Mesa/Intel wrapper is the same choice.
        exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkgs.code-cursor}/bin/cursor "$@"
      '';
    })
  ];
}
