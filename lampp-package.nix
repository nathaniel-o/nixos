# LAMPP stack (Apache, MariaDB, PHP), laid out like XAMPP.
# The flake installs this. Mutable state lives in /var/lib/lampp, not in /home
# and not in the Nix store. /opt/lampp is a symlink to that directory.
#
# Apache listens on 127.0.0.1:8080. MariaDB listens on 127.0.0.1:3306.
# AdminNeo is at http://127.0.0.1:8080/phpmyadmin
# Firefly, once restored, is at http://127.0.0.1:8080/CYS/
# The MariaDB root password is generated under /var/lib/lampp/etc/. It is not
# in this file. Database contents are not part of the flake.
{ pkgs }:

let
  apache = pkgs.apacheHttpd;
  mariadb = pkgs.mariadb;
  php = pkgs.php85;
  adminneo = pkgs.adminneo;
  perl = pkgs.perl;
  rsync = pkgs.rsync;

  lampp = pkgs.writeShellScriptBin "lampp" ''
    set -euo pipefail

    # sudo sets HOME=/root, which would start a second stack at /root/lampp
    # and fail because port 3306 is already taken by the user install.
    if [[ "$(id -u)" -eq 0 ]]; then
      owner="''${SUDO_USER:-}"
      if [[ -z "$owner" || "$owner" == root ]]; then
        if [[ -d /opt/lampp ]]; then
          owner="$(stat -c %U /opt/lampp)"
        fi
      fi
      if [[ -n "$owner" && "$owner" != root ]]; then
        printf '==> Refusing to run MariaDB as root; continuing as %s\n' "$owner"
        exec runuser -u "$owner" -- "$(readlink -f "$0")" "$@"
      fi
    fi

    if [[ -n "''${LAMPP_ROOT:-}" ]]; then
      ROOT="$LAMPP_ROOT"
    else
      ROOT=/var/lib/lampp
    fi
    APACHE="${apache}"
    PHP="${php}"
    MARIADB="${mariadb}"
    ADMINNEO="${adminneo}"
    PERL="${perl}"
    RSYNC="${rsync}"

    die() { printf 'lampp: %s\n' "$*" >&2; exit 1; }
    log() { printf '==> %s\n' "$*"; }

    usage() {
      cat <<EOF
    Usage: lampp {install|start|stop|restart|status|startapache|stopapache|startmysql|stopmysql}

    Root: $ROOT
    Web:  http://127.0.0.1:8080/   (port 80 only when started as root)
    DB:   root, password in $ROOT/etc/mysql-root.password
          socket: $ROOT/var/mysql.sock
          port:   127.0.0.1:3306
    EOF
      exit "''${1:-0}"
    }

    ensure_layout() {
      mkdir -p "$ROOT"/{htdocs,logs,var,mysql,bin,etc,tmp}
      ln -sfn "$PHP/bin/php" "$ROOT/bin/php"
      ln -sfn "$PHP/bin/php-fpm" "$ROOT/bin/php-fpm"
      ln -sfn "$MARIADB/bin/mariadb" "$ROOT/bin/mariadb"
      ln -sfn "$MARIADB/bin/mariadb" "$ROOT/bin/mysql"
      ln -sfn "$MARIADB/bin/mariadb-dump" "$ROOT/bin/mariadb-dump"
      ln -sfn "$MARIADB/bin/mariadb-dump" "$ROOT/bin/mysqldump"
      ln -sfn "$MARIADB/bin/mariadbd" "$ROOT/bin/mariadbd"
      ln -sfn "$MARIADB/bin/mariadbd" "$ROOT/bin/mysqld"
      ln -sfn "$MARIADB/bin/mariadb-admin" "$ROOT/bin/mariadb-admin"
      ln -sfn "$MARIADB/bin/mariadb-admin" "$ROOT/bin/mysqladmin"
      ln -sfn "$APACHE/bin/httpd" "$ROOT/bin/httpd"
      ln -sfn "$PERL/bin/perl" "$ROOT/bin/perl"
      ln -sfn "$RSYNC/bin/rsync" "$ROOT/bin/rsync"
      ln -sfn "$(readlink -f "$0")" "$ROOT/lampp"
      if [[ ! -e "$ROOT/htdocs/index.php" ]]; then
        cat > "$ROOT/htdocs/index.php" <<'PHP'
    <?php
    if (isset($_GET['phpinfo'])) {
        phpinfo();
        exit;
    }
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>LAMPP</title>
      <style>
        body { font-family: sans-serif; max-width: 40rem; margin: 3rem auto; line-height: 1.45; }
        code { background: #f2f2f2; padding: 0.1rem 0.3rem; }
      </style>
    </head>
    <body>
      <h1>LAMPP</h1>
      <p>Apache, MariaDB, and PHP <?php echo htmlspecialchars(PHP_VERSION); ?>.</p>
      <ul>
        <li><a href="/phpmyadmin/">Database</a> (AdminNeo)</li>
        <li><a href="/?phpinfo=1">phpinfo</a></li>
        <li>Document root: <code><?php echo htmlspecialchars(__DIR__); ?></code></li>
      </ul>
      <p>MariaDB user <code>root</code>. Password is in <code>etc/mysql-root.password</code> under the LAMPP root. Localhost only.</p>
    </body>
    </html>
    PHP
      fi
      # The Firefly tree and its database are restored separately. Until then,
      # /CYS should answer so the alias is visibly part of this stack.
      if [[ ! -e "$ROOT/htdocs/CYS/public/index.php" ]]; then
        mkdir -p "$ROOT/htdocs/CYS/public"
        cat > "$ROOT/htdocs/CYS/public/index.php" <<'PHP'
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Firefly</title>
    </head>
    <body>
      <h1>Firefly</h1>
      <p>This LAMPP stack serves <code>/CYS</code> from <code>htdocs/CYS/public</code>.</p>
      <p>The Firefly files, <code>.env</code>, and database are not in the NixOS flake. Restore them with <code>nso_import</code>.</p>
    </body>
    </html>
    PHP
      fi
    }

    ensure_db_password() {
      local file="$ROOT/etc/mysql-root.password"
      if [[ ! -s "$file" ]]; then
        umask 077
        od -An -N18 -tx1 /dev/urandom | tr -d ' \n' > "$file"
        printf '\n' >> "$file"
      fi
      chmod 600 "$file"
    }

    db_password() {
      tr -d '\n' < "$ROOT/etc/mysql-root.password"
    }

    write_mysql_cnf() {
      local pass=""
      [[ -s "$ROOT/etc/mysql-root.password" ]] && pass="$(db_password)"
      cat > "$ROOT/etc/my.cnf" <<EOF
    [mysqld]
    datadir = $ROOT/mysql
    socket = $ROOT/var/mysql.sock
    pid-file = $ROOT/var/mysql.pid
    bind-address = 127.0.0.1
    port = 3306
    log-error = $ROOT/logs/mysql-error.log
    tmpdir = $ROOT/tmp

    [client]
    socket = $ROOT/var/mysql.sock
    user = root
    password = ''${pass}
    EOF
      chmod 600 "$ROOT/etc/my.cnf"
    }

    write_phpfpm_conf() {
      local user group
      user="$(id -un)"
      group="$(id -gn)"
      cat > "$ROOT/etc/php-fpm.conf" <<EOF
    [global]
    error_log = $ROOT/logs/php-fpm.log
    daemonize = yes
    pid = $ROOT/var/php-fpm.pid

    [lampp]
    user = $user
    group = $group
    listen = $ROOT/var/php-fpm.sock
    listen.owner = $user
    listen.group = $group
    listen.mode = 0660
    pm = ondemand
    pm.max_children = 8
    pm.process_idle_timeout = 10s
    php_admin_value[memory_limit] = 256M
    php_admin_value[upload_max_filesize] = 64M
    php_admin_value[post_max_size] = 64M
    php_admin_value[max_execution_time] = 120
    php_admin_value[display_errors] = On
    php_admin_value[date.timezone] = America/New_York
    php_admin_value[mysqli.default_socket] = $ROOT/var/mysql.sock
    php_admin_value[pdo_mysql.default_socket] = $ROOT/var/mysql.sock
    EOF
    }

    write_httpd_conf() {
      local port="$1"
      cat > "$ROOT/etc/httpd.conf" <<EOF
    ServerRoot "$APACHE"
    Listen 127.0.0.1:$port
    Listen [::1]:$port
    ServerName localhost
    PidFile "$ROOT/var/httpd.pid"
    ErrorLog "$ROOT/logs/httpd-error.log"
    CustomLog "$ROOT/logs/httpd-access.log" common

    LoadModule mpm_event_module modules/mod_mpm_event.so
    LoadModule authn_core_module modules/mod_authn_core.so
    LoadModule authz_core_module modules/mod_authz_core.so
    LoadModule authz_host_module modules/mod_authz_host.so
    LoadModule dir_module modules/mod_dir.so
    LoadModule mime_module modules/mod_mime.so
    LoadModule log_config_module modules/mod_log_config.so
    LoadModule alias_module modules/mod_alias.so
    LoadModule rewrite_module modules/mod_rewrite.so
    LoadModule autoindex_module modules/mod_autoindex.so
    LoadModule unixd_module modules/mod_unixd.so
    LoadModule proxy_module modules/mod_proxy.so
    LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so

    <Directory />
        Require all denied
    </Directory>

    <Directory /nix/store>
        Require all granted
    </Directory>

    DocumentRoot "$ROOT/htdocs"
    <Directory "$ROOT/htdocs">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>

    # Firefly lives in htdocs/CYS; only its public/ directory is the site.
    Alias /CYS "$ROOT/htdocs/CYS/public"
    <Directory "$ROOT/htdocs/CYS">
        AllowOverride None
    </Directory>
    <Directory "$ROOT/htdocs/CYS/public">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>

    Alias /phpmyadmin "$ADMINNEO/"
    <Directory "$ADMINNEO">
        Options FollowSymLinks
        AllowOverride None
        Require all granted
        DirectoryIndex index.php
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:$ROOT/var/php-fpm.sock|fcgi://localhost"
    </FilesMatch>

    TypesConfig "$APACHE/conf/mime.types"
    EOF
    }

    mysql_running() {
      [[ -S "$ROOT/var/mysql.sock" ]] || return 1
      "$MARIADB/bin/mariadb-admin" --defaults-file="$ROOT/etc/my.cnf" ping >/dev/null 2>&1
    }

    pid_running() {
      local file="$1"
      [[ -f "$file" ]] || return 1
      local pid
      pid="$(cat "$file" 2>/dev/null || true)"
      [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
    }

    init_mysql() {
      ensure_db_password
      write_mysql_cnf
      if [[ ! -d "$ROOT/mysql/mysql" ]]; then
        log "Initializing MariaDB data directory"
        "$MARIADB/bin/mariadb-install-db" \
          --datadir="$ROOT/mysql" \
          --basedir="$MARIADB" \
          --auth-root-authentication-method=normal \
          --skip-test-db
      fi
      chmod 700 "$ROOT/mysql"
    }

    grant_local_root() {
      local pass sql
      pass="$(db_password)"
      sql="ALTER USER 'root'@'localhost' IDENTIFIED BY '$(db_password)';"
      # Blank password still works until the first successful ALTER.
      "$MARIADB/bin/mariadb" --socket="$ROOT/var/mysql.sock" --user=root --password= -e "$sql" \
        || "$MARIADB/bin/mariadb" --defaults-file="$ROOT/etc/my.cnf" -e "$sql"
      sql="CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$(db_password)'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY '$(db_password)'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;"
      "$MARIADB/bin/mariadb" --socket="$ROOT/var/mysql.sock" --user=root --password="$pass" -e "$sql"
    }

    start_mysql() {
      ensure_layout
      init_mysql
      if mysql_running; then
        log "MariaDB already running"
      else
        log "Starting MariaDB on 127.0.0.1:3306"
        "$MARIADB/bin/mariadbd" --defaults-file="$ROOT/etc/my.cnf" &
        local i
        for i in $(seq 1 50); do
          if mysql_running; then
            break
          fi
          sleep 0.2
        done
        if ! mysql_running; then
          if [[ -f "$ROOT/logs/mysql-error.log" ]]; then
            tail -n 20 "$ROOT/logs/mysql-error.log" >&2
          fi
          die "MariaDB did not become ready. See $ROOT/logs/mysql-error.log"
        fi
      fi
      grant_local_root
    }

    stop_mysql() {
      if [[ -S "$ROOT/var/mysql.sock" ]]; then
        log "Stopping MariaDB"
        "$MARIADB/bin/mariadb-admin" --defaults-file="$ROOT/etc/my.cnf" shutdown || true
      else
        log "MariaDB is not running"
      fi
    }

    start_phpfpm() {
      write_phpfpm_conf
      if pid_running "$ROOT/var/php-fpm.pid"; then
        log "PHP-FPM already running"
        return 0
      fi
      log "Starting PHP-FPM"
      "$PHP/bin/php-fpm" --fpm-config "$ROOT/etc/php-fpm.conf"
    }

    stop_phpfpm() {
      if pid_running "$ROOT/var/php-fpm.pid"; then
        log "Stopping PHP-FPM"
        kill -QUIT "$(cat "$ROOT/var/php-fpm.pid")" || true
      else
        log "PHP-FPM is not running"
      fi
    }

    start_apache() {
      ensure_layout
      local port=8080
      if [[ "$(id -u)" -eq 0 ]]; then
        port=80
      fi
      write_httpd_conf "$port"
      printf '%s\n' "$port" > "$ROOT/var/http-port"
      if pid_running "$ROOT/var/httpd.pid"; then
        log "Apache already running"
        return 0
      fi
      log "Starting Apache on 127.0.0.1:$port"
      "$APACHE/bin/httpd" -f "$ROOT/etc/httpd.conf" -k start
    }

    stop_apache() {
      if [[ ! -f "$ROOT/etc/httpd.conf" ]]; then
        log "Apache is not running"
        return 0
      fi
      if pid_running "$ROOT/var/httpd.pid"; then
        log "Stopping Apache"
        "$APACHE/bin/httpd" -f "$ROOT/etc/httpd.conf" -k stop || true
      else
        log "Apache is not running"
      fi
    }

    cmd_status() {
      local port="8080"
      [[ -f "$ROOT/var/http-port" ]] && port="$(cat "$ROOT/var/http-port")"
      if pid_running "$ROOT/var/httpd.pid"; then
        log "Apache: running  http://127.0.0.1:$port/"
      else
        log "Apache: stopped"
      fi
      if pid_running "$ROOT/var/php-fpm.pid"; then
        log "PHP-FPM: running"
      else
        log "PHP-FPM: stopped"
      fi
      if mysql_running; then
        log "MariaDB: running  socket $ROOT/var/mysql.sock"
      else
        log "MariaDB: stopped"
      fi
      log "Document root: $ROOT/htdocs"
    }

    case "''${1:-}" in
      ""|-h|--help|help) usage 0 ;;
      install) ensure_layout; write_mysql_cnf; write_phpfpm_conf; log "Installed at $ROOT" ;;
      start) start_mysql; start_phpfpm; start_apache; cmd_status ;;
      stop) stop_apache; stop_phpfpm; stop_mysql ;;
      restart) stop_apache; stop_phpfpm; stop_mysql; start_mysql; start_phpfpm; start_apache; cmd_status ;;
      status) cmd_status ;;
      startapache) start_phpfpm; start_apache; cmd_status ;;
      stopapache) stop_apache ;;
      startmysql) start_mysql; cmd_status ;;
      stopmysql) stop_mysql ;;
      *) die "unknown command: $1 (try lampp --help)" ;;
    esac
  '';
in
lampp
