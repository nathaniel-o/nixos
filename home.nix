# User profile for nathaniel.
# Personal programs only. The account, Plasma, and services stay in configuration.nix.
# Apply with: sudo nixos-rebuild switch --flake /etc/nixos#nixos
{ pkgs, ... }:
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

  home.packages = with pkgs; [
    vim
    wget
    git
    ghostty
    rofi
    brave
    neovim
    keepassxc
    firefly-iii
    microsoft-edge
    swift
    kdePackages.kate
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
