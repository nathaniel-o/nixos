# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Virtual output for phone-screen. VNC stays on localhost.
  boot.kernelModules = [ "vkms" ];

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  #   customize for ly / qtile per 
  #services.displayManager.ly.enable = true;
 # services.xserver = {
#	enable = true; 
#	autoRepeatDelay = 200;
#	autoRepeatInterval = 35;
#	windowManager.qtile.enable = true; 
  #};
   services.xserver.enable = true;
   services.printing.drivers = [ pkgs.pantum-driver ];

   hardware.sane = {
     enable = true;
     extraBackends = [ pkgs.pantum-driver ];
   };


  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.windowManager.qtile.enable = true;
  # Plasma's module would otherwise select itself at the login screen.
  # Plasma stays in the session menu.
  services.displayManager.defaultSession = "qtile";

	# Qtile enables GNOME Keyring and Plasma enables KWallet. The keyring
	# daemon that actually answers apps comes up locked, so Brave, Edge, and
	# Cursor ask for a password. Leave both off. Plasma still ships the
	# KWallet binaries; nothing starts them, and their D-Bus activation
	# files are dropped below.
	services.gnome.gnome-keyring.enable = false;
	security.pam.services.login.kwallet.enable = lib.mkForce false;
	security.pam.services.kde.kwallet.enable = lib.mkForce false;
	environment.extraSetup = ''
	  rm -f \
	    "$out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service" \
	    "$out/share/dbus-1/services/org.kde.kwalletd5.service" \
	    "$out/share/dbus-1/services/org.kde.kwalletd6.service" \
	    "$out/share/dbus-1/services/org.kde.kwalletmanager.service" \
	    "$out/share/dbus-1/services/org.kde.secretprompter.service" \
	    "$out/share/dbus-1/services/org.kde.secretservicecompat.service"
	'';

  # Qtile is a wlroots compositor. Plasma's portal cannot capture it.
  # ~/.config/qtile/config.py sets XDG_CURRENT_DESKTOP=qtile and imports
  # that into the user session so this file is the one portals load.
  xdg.portal.wlr = {
    enable = true;
    settings.screencast = {
      max_fps = 30;
      chooser_type = "simple";
      chooser_cmd = "${pkgs.slurp}/bin/slurp -f 'Monitor: %o' -or";
    };
  };
  xdg.portal.config.qtile = {
    default = [ "gtk" ];
    "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
    "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
    "org.freedesktop.impl.portal.Inhibit" = [ "none" ];
  };
  services.xserver.displayManager.importedVariables = [
    "XDG_CURRENT_DESKTOP"
    "XDG_SESSION_DESKTOP"
    "WAYLAND_DISPLAY"
    "XDG_SESSION_TYPE"
  ];


  # Qtile does not ship a lock screen. `loginctl lock-session` is answered by
  # Plasma's kscreenlocker, so a Qtile session either failed to lock or showed
  # the Plasma greeter. swaylock uses the Wayland session-lock protocol Qtile
  # implements. i3lock covers the X11 Qtile session. Plasma still uses
  # kscreenlocker, because session-lock defers to it there.
  programs.i3lock.enable = true;
  security.pam.services.swaylock = { };
  environment.systemPackages = [
    pkgs.swayidle
    pkgs.swaylock
    pkgs.xss-lock
    (pkgs.writeShellScriptBin "session-lock" ''
      set -eu
      foreground=0
      if [ "''${1:-}" = "--foreground" ]; then
        foreground=1
      fi

      # SDDM names the Wayland session "plasma" and the X11 session "plasmax11".
      # startplasma also sets XDG_CURRENT_DESKTOP=KDE.
      case "''${DESKTOP_SESSION:-}" in
        plasma*)
          exec loginctl lock-session
          ;;
      esac
      case "''${XDG_CURRENT_DESKTOP:-}" in
        *KDE*)
          exec loginctl lock-session
          ;;
      esac

      if [ "''${XDG_SESSION_TYPE:-}" = "wayland" ]; then
        # Colors follow the Qtile bar. -f returns once the lock is visible,
        # so suspend is not stuck behind the password prompt. xss-lock needs
        # the locker to stay in the foreground until unlock.
        # This swaylock has no --clock. Those options made it exit before
        # locking, so the menu did nothing and suspend never asked for a
        # password. The indicator stays visible so the screen is not a blank
        # panel, which is what looked like a lost display.
        args=(
          --color 191724
          --inside-color 26233a
          --ring-color ebbcba
          --line-color 26233a
          --separator-color 191724
          --text-color e0def4
          --key-hl-color 9ccfd8
          --bs-hl-color eb6f92
          --indicator-radius 120
          --indicator-thickness 10
          --indicator-idle-visible
        )
        if [ "$foreground" -eq 0 ]; then
          args=(-f "''${args[@]}")
        fi
        log="$HOME/.local/state/qtile/session-lock.log"
        mkdir -p "$(dirname "$log")"
        echo "$(date --iso-8601=seconds) swaylock" >>"$log"
        exec swaylock "''${args[@]}" >>"$log" 2>&1
      fi

      exec i3lock -c 191724
    '')
  ];


  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

   #Enable BlueTooth 
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  # Optional: GUI management for non-desktop environments
  #services.blueman.enable = true;
  #to pair by cmd, see bluez pkg &/ load prioprietary drivers: 
  #hardware.enableAllFirmware = true; 
  
  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;


  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    # jack.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # allow Docker
virtualisation.docker.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."nathaniel" = {
    isNormalUser = true;
    description = "nathaniel";
    extraGroups = [ "networkmanager" "wheel" "lp" "scanner" "docker"];
  };


  # Install firefox.
  programs.firefox.enable = true;
  # Install Zoom
  programs.zoom-us.enable = true;
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # User programs live in home.nix.
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:
  services.upower.enable = true; # show battery info 
  powerManagement.enable = true;
  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?

}
