# Installs the LAMPP stack and starts it at boot.
# Binaries come from the Nix store. Writable state is /var/lib/lampp:
# document root, MariaDB data, logs, and the generated root password.
# None of that state is in the flake. /opt/lampp and ~/lampp point at it
# so existing scripts keep their paths.
{ pkgs, ... }:
let
  lampp = pkgs.callPackage ./lampp-package.nix { };
  state = "/var/lib/lampp";
in
{
  environment.systemPackages = [ lampp ];

  system.activationScripts.lampp = {
    deps = [ "users" ];
    text = ''
      home=/home/nathaniel/lampp
      state=${state}
      if [ -d "$home" ] && [ ! -L "$home" ]; then
        if [ -x "$home/lampp" ]; then
          runuser -u nathaniel -- "$home/lampp" stop || true
        fi
        if [ -e "$state" ]; then
          printf 'lampp: %s already exists, so %s was left in place\n' "$state" "$home" >&2
        else
          mv "$home" "$state"
        fi
      fi
      if [ ! -d "$home" ] || [ -L "$home" ]; then
        mkdir -p "$state"
        chown nathaniel:users "$state"
        ln -sfn "$state" /opt/lampp
        if [ ! -e "$home" ]; then
          ln -sfn "$state" "$home"
        fi
      fi
    '';
  };

  systemd.services.lampp = {
    description = "LAMPP (Apache, MariaDB, PHP)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "nathaniel";
      Group = "users";
      ExecStart = "${lampp}/bin/lampp start";
      ExecStop = "${lampp}/bin/lampp stop";
      TimeoutStartSec = "120";
    };
  };
}
