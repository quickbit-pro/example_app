/* Customer installation guidance. No network calls, credentials, or DOM writes. */
(function (global) {
  'use strict';
  const sh = value => "'" + String(value).replace(/'/g, "'\\''") + "'";
  const py = value => JSON.stringify(String(value));
  const hostPattern = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;
  const link = (label, url) => ({label, url});
  // Every command block says where it runs. The three places are the developer's
  // own computer, the customer's Ubuntu server (over SSH) and a psql session
  // signed in as the database administrator.
  const WHERE = Object.freeze(['Laptop', 'Server', 'Database admin']);
  // step(title, where, text, {watch, expect, code, language}).
  // text = "What this does". watch = "Watch out". expect = "What you should see".
  const step = (title, where, text, extra = {}) => {
    if (where !== null && !WHERE.includes(where)) throw new Error('Unknown step location: ' + where);
    return {title, ...(where ? {where} : {}), text, ...(extra.watch ? {watch: extra.watch} : {}), ...(extra.expect ? {expect: extra.expect} : {}), ...(extra.code ? {code: extra.code, language: extra.language || 'bash'} : {})};
  };
  const term = (name, definition) => ({term: name, definition});

  function validate(input) {
    const p = input || {};
    const errors = [];
    if (!/^[a-z][a-z0-9_-]{1,23}$/.test(p.brandId || '')) errors.push('Brand ID must be 2–24 lowercase letters, digits, underscores or hyphens, beginning with a letter.');
    if (!p.appName || p.appName.length > 80 || /[\x00-\x1f\x7f]/.test(p.appName)) errors.push('App name must be 1–80 characters without control characters.');
    for (const key of ['apiDomain', 'appDomain', 'adminDomain']) {
      if (!hostPattern.test(p[key] || '')) errors.push(key + ' must be a DNS hostname without a scheme, path, port, or wildcard.');
    }
    if (new Set([p.apiDomain, p.appDomain, p.adminDomain]).size !== 3) errors.push('Use three different hostnames for API, PWA and admin.');
    if (!['local', 'managed'].includes(p.dbMode)) errors.push('Choose local or managed PostgreSQL.');
    for (const key of ['dbName', 'dbUser']) if (!/^[a-z][a-z0-9_]{0,39}$/.test(p[key] || '')) errors.push(key + ' must be 1–40 lowercase letters, digits or underscores, beginning with a letter.');
    if (!Number.isInteger(Number(p.dbPort)) || Number(p.dbPort) < 1 || Number(p.dbPort) > 65535) errors.push('Database port must be 1–65535.');
    if (p.dbMode === 'local' && (!['127.0.0.1', 'localhost'].includes(p.dbHost) || Number(p.dbPort) !== 5432)) errors.push('Local setup uses PostgreSQL on 127.0.0.1:5432.');
    if (p.dbMode === 'managed' && !hostPattern.test(p.dbHost || '')) errors.push('Managed database host must be its certificate-matching DNS hostname.');
    if (p.dbMode === 'managed' && p.dbSslMode !== 'VerifyFull') errors.push('Managed PostgreSQL requires SSL Mode VerifyFull.');
    if (p.dbMode === 'local' && p.dbSslMode !== 'Disable') errors.push('This local-only loopback recipe uses SSL Mode Disable.');
    if (p.dbRootCert && (!/^\/[A-Za-z0-9_./-]+$/.test(p.dbRootCert) || p.dbRootCert.split('/').includes('..'))) errors.push('Root certificate must be an absolute Linux path without spaces or parent traversal.');
    if (p.primaryColor && (typeof p.primaryColor !== 'string' || !/^#(?:[0-9a-f]{6}|ff[0-9a-f]{6})$/i.test(p.primaryColor))) errors.push('Primary color must be opaque #RRGGBB or #FFRRGGBB hex.');
    if (p.supportEmail && (typeof p.supportEmail !== 'string' || p.supportEmail.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(p.supportEmail))) errors.push('Support email must be a valid email address.');
    if (p.legalEntity && (typeof p.legalEntity !== 'string' || p.legalEntity.length > 200 || /[\x00-\x1f\x7f]/.test(p.legalEntity))) errors.push('Legal entity must be at most 200 characters without control characters.');
    for (const key of ['termsUrl', 'privacyUrl']) {
      if (!p[key]) continue;
      try {
        const url = new URL(p[key]);
        if (typeof p[key] !== 'string' || /[\x00-\x20\x7f]/.test(p[key]) || url.protocol !== 'https:' || !url.hostname || url.username || url.password) throw new Error('invalid');
      } catch (_) { errors.push(key + ' must be an HTTPS URL without credentials or whitespace.'); }
    }
    const repo = p.repoUrl || '';
    if (!/^https:\/\/[a-z0-9.-]+\/[a-zA-Z0-9_./-]+(?:\.git)?$/.test(repo) && !/^git@[a-z0-9.-]+:[a-zA-Z0-9_./-]+(?:\.git)?$/.test(repo)) errors.push('Use an HTTPS or git@host:path repository URL without credentials, query strings, or shell syntax.');
    return errors;
  }

  function render(p) {
    const errors = validate(p);
    if (errors.length) throw new Error(errors.join('\n'));
    const id = p.brandId;
    const svc = 'app-' + id;
    const root = '/opt/' + id;
    const cfg = '/etc/' + id;
    const overlay = cfg + '/appsettings.Production.json';
    const dbHost = p.dbMode === 'local' ? '127.0.0.1' : p.dbHost;
    const apiUrl = 'https://' + p.apiDomain;
    const appUrl = 'https://' + p.appDomain;
    const adminUrl = 'https://' + p.adminDomain;
    const dbEnv = ['export PGHOST=' + sh(dbHost), 'export PGPORT=' + sh(p.dbPort), 'export PGDATABASE=' + sh(p.dbName), 'export PGUSER=' + sh(p.dbUser), 'export PGSSLMODE=' + sh(p.dbMode === 'local' ? 'disable' : 'verify-full'), ...(p.dbMode === 'managed' ? ['export PGSSLROOTCERT=' + sh(p.dbRootCert || '/etc/ssl/certs/ca-certificates.crt')] : [])].join('\n');
    const publicSettings = {
      ConnectionStrings: {NeoBankingDb: ''},
      Jwt: {Issuer: id, Audience: id + '.api', SigningKey: '', ClockSkewSeconds: 60},
      Company: {
        InstallationId: id, Name: p.legalEntity || p.appName, BrandName: p.appName,
        Branding: {LogoUrl: appUrl + '/branding/logo.png', PrimaryColor: p.primaryColor ? '#' + p.primaryColor.slice(-6).toUpperCase() : '#2563EB', SupportEmail: p.supportEmail || '', TermsUrl: p.termsUrl || '', PrivacyUrl: p.privacyUrl || ''},
        Features: {ReferralsEnabled: false, ReferralRegistrationMode: 'optional', VouchersEnabled: false, ExistingAccountClaimEnabled: false, BoomFiExchangeEnabled: false, WalletOutflowsEnabled: false, EqualsMoneyEnabled: false, BusinessOnboardingEnabled: false}
      },
      Hoppa: {BaseUrl: '', ApiKey: '', WebhookSecret: '', SumSubWebhookSecret: '', PortfolioEstimatePath: '/api/v2/prices/estimated-total-assets', TimeoutSeconds: 30},
      Email: {Provider: 'sendgrid', FromEmail: '', FromName: p.appName, ReplyToEmail: '', RequireVerifiedEmailForLogin: true, SendGrid: {ApiKey: '', SandboxMode: false}},
      PushNotifications: {Enabled: false, FirebaseProjectId: '', ServiceAccountPath: ''},
      MarketData: {Enabled: false},
      Cors: {AllowedOrigins: [appUrl, adminUrl]},
      AllowedHosts: [p.apiDomain, 'localhost', '127.0.0.1'].join(';')
    };
    const configCommand = `sudo python3 - <<'CUSTOMER_CONFIG_PY'
import getpass, grp, json, os, secrets
from urllib.parse import urlparse
path = ${py(overlay)}
if os.path.exists(path):
    raise SystemExit('Configuration already exists; edit it deliberately with sudoedit instead.')
settings = json.loads(${py(JSON.stringify(publicSettings))})
def prompt(label):
    with open('/dev/tty', 'r+') as tty:
        tty.write(label + ': '); tty.flush()
        value = tty.readline().strip()
    if not value:
        raise SystemExit(label + ' is required')
    return value
def secret(label):
    value = getpass.getpass(label + ': ')
    if not value:
        raise SystemExit(label + ' is required')
    return value
def conn_value(value):
    return '"' + value.replace('"', '""') + '"'
db_password = secret('Database role password created earlier')
parts = {'Host': ${py(dbHost)}, 'Port': ${py(p.dbPort)}, 'Database': ${py(p.dbName)}, 'Username': ${py(p.dbUser)}, 'Password': db_password, 'SSL Mode': ${py(p.dbSslMode)}}
${p.dbMode === 'managed' && p.dbRootCert ? "parts['Root Certificate'] = " + py(p.dbRootCert) : '# Local connections remain on loopback; managed connections verify hostname and CA.'}
settings['ConnectionStrings']['NeoBankingDb'] = ';'.join(key + '=' + conn_value(value) for key, value in parts.items())
settings['Jwt']['SigningKey'] = secrets.token_urlsafe(48)
${p.legalEntity ? '# Legal company name supplied by the customer wizard.' : "settings['Company']['Name'] = prompt('Customer legal company name')"}
${p.primaryColor ? '# Primary color supplied by the customer wizard.' : "settings['Company']['Branding']['PrimaryColor'] = prompt('Brand primary color, for example #621A96')"}
${p.supportEmail ? '# Support email supplied by the customer wizard.' : "settings['Company']['Branding']['SupportEmail'] = prompt('Customer support email')"}
${p.termsUrl ? '# Terms URL supplied by the customer wizard.' : "settings['Company']['Branding']['TermsUrl'] = prompt('Published HTTPS terms URL')"}
${p.privacyUrl ? '# Privacy URL supplied by the customer wizard.' : "settings['Company']['Branding']['PrivacyUrl'] = prompt('Published HTTPS privacy URL')"}
provider_url = prompt('Customer Hoppa provider base URL supplied by provider')
parsed = urlparse(provider_url)
if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
    raise SystemExit('Provider URL must be HTTPS without credentials')
settings['Hoppa']['BaseUrl'] = provider_url.rstrip('/') + '/'
settings['Hoppa']['ApiKey'] = secret('Customer Hoppa provider API key')
settings['Hoppa']['WebhookSecret'] = secret('Hoppa webhook signing secret agreed with provider')
settings['Hoppa']['SumSubWebhookSecret'] = secret('Sumsub webhook signing secret agreed with provider')
settings['Email']['FromEmail'] = prompt('Verified SendGrid sender address')
settings['Email']['ReplyToEmail'] = settings['Company']['Branding']['SupportEmail']
settings['Email']['SendGrid']['ApiKey'] = secret('Customer SendGrid API key')
os.umask(0o077)
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
with os.fdopen(fd, 'w') as output:
    json.dump(settings, output, indent=2); output.write('\\n')
os.chown(path, 0, grp.getgrnam(${py(svc)}).gr_gid)
os.chmod(path, 0o640)
print('Customer configuration saved. No secrets were printed.')
CUSTOMER_CONFIG_PY`;
    const unit = `[Unit]
Description=${id} customer API
After=network-online.target
Wants=network-online.target

[Service]
User=${svc}
Group=${svc}
WorkingDirectory=${root}/current/api
ExecStart=/usr/bin/dotnet ${root}/current/api/NeoBanking.Api.dll
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://127.0.0.1:5300
Environment=HOME=/var/lib/${svc}
StateDirectory=${svc}
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
UMask=0077

[Install]
WantedBy=multi-user.target`;
    const nginx = `# Dedicated customer installation, direct internet -> nginx -> loopback API.
server {
    listen 80;
    listen [::]:80;
    server_name ${p.apiDomain};
    client_max_body_size 20m;
    location / {
        proxy_pass http://127.0.0.1:5300;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        # Overwrite untrusted incoming headers; API reads the first address.
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 90s;
    }
}
server {
    listen 80;
    listen [::]:80;
    server_name ${p.appDomain};
    root ${root}/current/app;
    index index.html;
    gzip on;
    gzip_vary on;
    gzip_types application/javascript application/json application/wasm text/css image/svg+xml;
    # Asset names are not all content-hashed: revalidate on every release.
    location ~* \\.(js|json|wasm|html|css|png|jpg|jpeg|svg|ico|webp|woff2?|ttf)$ {
        add_header Cache-Control "no-cache" always;
        add_header Service-Worker-Allowed "/" always;
        try_files $uri =404;
    }
    location / {
        add_header Cache-Control "no-cache" always;
        try_files $uri $uri/ /index.html;
    }
}
server {
    listen 80;
    listen [::]:80;
    server_name ${p.adminDomain};
    root ${root}/current/admin;
    index index.html;
    gzip on;
    gzip_vary on;
    gzip_types application/javascript application/json text/css image/svg+xml;
    location /assets/ {
        add_header Cache-Control "public, max-age=31536000, immutable" always;
        try_files $uri =404;
    }
    location / {
        add_header Cache-Control "no-cache" always;
        try_files $uri $uri/ /index.html;
    }
}`;
    const hbaRuleV4 = `host  ${p.dbName}  ${p.dbUser}  127.0.0.1/32  scram-sha-256`;
    const hbaRuleV6 = `host  ${p.dbName}  ${p.dbUser}  ::1/128       scram-sha-256`;
    const hbaCommand = `set -euo pipefail
hba="$(sudo -u postgres psql -X -Atc 'SHOW hba_file;')"
rule_v4=${sh(hbaRuleV4)}
rule_v6=${sh(hbaRuleV6)}
if sudo grep -qxF "$rule_v4" "$hba" && sudo grep -qxF "$rule_v6" "$hba"; then
  echo "Both rules are already present in $hba. Nothing was changed."
else
  backup="$hba.before-${id}-$(date -u +%Y%m%dT%H%M%SZ)"
  sudo cp -p "$hba" "$backup"
  printf '\\n# Added for the %s application role (customer setup guide)\\n%s\\n%s\\n' ${sh(id)} "$rule_v4" "$rule_v6" | sudo tee -a "$hba" > /dev/null
  echo "Changes made to $hba (backup kept at $backup):"
  sudo diff -u "$backup" "$hba" || true
fi
sudo systemctl reload postgresql
sudo -u postgres psql -X -c "SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules WHERE error IS NULL ORDER BY line_number;"
${dbEnv}
psql -X -W -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user, version();'`;
    const overlayInspect = `sudo python3 - <<'CUSTOMER_CHECK_PY'
import json
with open(${py(overlay)}) as source:
    settings = json.load(source)
parts = dict(item.split('=', 1) for item in settings['ConnectionStrings']['NeoBankingDb'].split(';') if '=' in item)
for key in ('Host', 'Port', 'Database', 'Username', 'SSL Mode', 'Root Certificate'):
    if key in parts:
        print(key + ' = ' + parts[key])
print('Password set: ' + ('yes' if parts.get('Password', '""') not in ('""', '') else 'NO'))
print('Jwt:SigningKey length: ' + str(len(settings['Jwt']['SigningKey'])))
print('Cors:AllowedOrigins = ' + json.dumps(settings['Cors']['AllowedOrigins']))
print('Hoppa:BaseUrl = ' + settings['Hoppa']['BaseUrl'])
CUSTOMER_CHECK_PY`;
    const sections = [
      {id: 'server-scope', title: '1. Agree the customer handoff', summary: 'This guide installs one customer app on one brand-new Linux server. The server gets three public addresses (hostnames): one for the API, one for the web app and one for the admin website. Nothing in this section runs a command. It lists who provides what, so nobody is blocked halfway through.', outline: ['Confirm what the customer provides: server, domains, database, repository, artwork.', 'Confirm what the delivery team provides: reviewed configuration, a tested release, an owner for updates.', 'Learn the folder and service names used by every later command.'], steps: [
        step('Customer supplies', null, `A server running Ubuntu Server 24.04 LTS, with SSH access for an administrator who can use sudo. Control over DNS (the address book of the internet) for ${p.apiDomain}, ${p.appDomain} and ${p.adminDomain}. A dedicated PostgreSQL database (see section 3). A customer-owned copy of the source repository. Brand assets and approved legal and support URLs. A practical starting size is 2 vCPU, 4 GB RAM and 30 GB SSD when builds run elsewhere.`, {watch: 'Measure real load and database growth before committing to a server size. Nothing in this guide resizes a server for you.'}),
        step('Delivery team supplies', null, 'The reviewed app configuration plus its referenced asset files. A tested release archive built from a recorded commit. One named owner for updates and backups.', {watch: 'Before the customer gets repository access, remove inherited credentials from the source tree and from Git history. Deleting a file from a release archive does not delete it from history. The branding JSON is public build configuration. Database passwords, JWT signing keys, provider keys and signing certificates belong only in customer-controlled secret storage.'}),
        step('Learn the installation paths', null, `Every command below uses the same names. Application files live in ${root}. Server-only settings live in ${cfg}. The API runs as the Linux service ${svc}. The API listens on local port 5300; nginx (the public web server) forwards internet traffic to it.`, {watch: 'Use only the commands in this guide for a customer server. Do not copy commands from other deployment notes in the repository; they may describe a different installation.'})
      ]},
      {id: 'server-network', title: '2. Prepare Linux, SSH and DNS', summary: 'You connect to the customer server over SSH (a secure remote terminal). You install the .NET runtime, nginx and a few tools. You open the firewall for SSH and web traffic, point the three domain names at the server, and create a locked-down Linux user that will run the API.', outline: ['Connect over SSH and confirm the Ubuntu version.', 'Install the .NET runtime, nginx and helper tools.', 'Open ports 22, 80 and 443 in the firewall.', 'Create DNS records for the three hostnames.', 'Create the service user and the application folders.'], steps: [
        step('Connect and verify the machine', 'Laptop', 'Opens a remote terminal on the customer server. Replace CUSTOMER_SSH_USER and CUSTOMER_SERVER_IP with the values the customer gave you. The remaining lines print the Ubuntu version and check that sudo works.', {watch: 'Keep this session open while you test a second login in another window. If you lock yourself out of SSH, nothing else in this guide can run. All server commands assume Bash on a new, dedicated Ubuntu server.', expect: 'The line "Ubuntu 24.04" and, after sudo -v, either a password prompt or no output at all.', code: `ssh CUSTOMER_SSH_USER@CUSTOMER_SERVER_IP
bash
. /etc/os-release
printf '%s %s\\n' "$NAME" "$VERSION_ID"
sudo -v`}),
        step('Install the runtime and basic tools', 'Server', 'Installs the ASP.NET Core 10 runtime (the program that runs the compiled API), nginx, the firewall tool ufw, the PostgreSQL client tools and a few helpers. The server does not need the full .NET SDK because the release is built on your laptop or in CI (section 5).', {expect: 'The last command lists Microsoft.AspNetCore.App 10.x and Microsoft.NETCore.App 10.x.', code: `sudo apt-get update
sudo apt-get install -y aspnetcore-runtime-10.0 nginx openssh-server ufw curl ca-certificates python3 postgresql-client-16 rsync tar snapd
dotnet --list-runtimes`}),
        step('Open the required ports', 'Server', 'Turns on the firewall and allows only SSH and web traffic (ports 80 and 443). Everything else stays closed.', {watch: 'If SSH uses a port other than 22, allow that port BEFORE enabling ufw. Mirror these rules in the cloud provider firewall or security group. Never expose PostgreSQL (5432) or the API port (5300) to the internet.', expect: 'Status: active, with OpenSSH and Nginx Full listed as ALLOW.', code: `sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status verbose`}),
        step('Point DNS at this server', null, `In the customer's DNS provider, create A records (name to IPv4 address) for ${p.apiDomain}, ${p.appDomain} and ${p.adminDomain}, all pointing at the server's public IP address. Add AAAA records (IPv6) only when the server really answers on that IPv6 address.`, {watch: 'Wait until public DNS returns the correct address before requesting HTTPS certificates in section 8. Certificate issuance and renewal need ports 80 and 443 reachable from the internet.'}),
        step('Create a runtime identity and directories', 'Server', `Creates a Linux system user named ${svc} that cannot log in and cannot change the application files. Creates ${root} for releases, ${cfg} for server-only settings and /var/lib/${svc} for runtime state.`, {watch: 'The service user only needs to read the release and its settings file. Secrets stay outside the release archive.', expect: 'No output. Errors mention an existing user or directory; that means this step already ran.', code: `sudo adduser --system --group --home /var/lib/${svc} --no-create-home --shell /usr/sbin/nologin ${sh(svc)}
sudo install -d -o root -g root -m 0755 ${sh(root)} ${sh(root + '/releases')}
sudo install -d -o root -g ${sh(svc)} -m 0750 ${sh(cfg)}
sudo install -d -o ${sh(svc)} -g ${sh(svc)} -m 0700 /var/lib/${svc}`})
      ], links: [link('Microsoft: .NET on Ubuntu 24.04', 'https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu-install#ubuntu-2404'), link('Ubuntu: firewall', 'https://ubuntu.com/server/docs/security-firewall/'), link('Ubuntu: OpenSSH', 'https://ubuntu.com/server/docs/how-to/security/openssh-server/')]},
      {id: 'database', title: '3. Prepare PostgreSQL', summary: p.dbMode === 'local' ? 'PostgreSQL is the database that stores users, cards and settings. In this recipe it runs on the same server and only accepts connections from that server (loopback, address 127.0.0.1). The API gets its own database login (a "role") that owns only the customer database and has no administrator rights.' : 'PostgreSQL is the database that stores users, cards and settings. In this recipe it runs as a managed service from a cloud provider. The API connects over a private network with TLS (encryption) and checks the server certificate, so nobody can impersonate the database.', outline: p.dbMode === 'local' ? ['Install PostgreSQL 16 and keep it on loopback.', 'Create the application role and an empty database.', 'Add password rules to pg_hba.conf with a script and test the login.'] : ['Provision the managed PostgreSQL instance on a private network.', 'Have the database administrator create the role and database.', 'Verify TLS and the login from the application server.'], steps: p.dbMode === 'local' ? [
        step('Install the database', 'Server', 'Installs PostgreSQL 16 from Ubuntu 24.04 and starts it. The two ALTER SYSTEM lines make PostgreSQL listen only on the local machine and store passwords with the modern SCRAM method.', {watch: 'Do not run ALTER SYSTEM on a database server shared with other applications without its administrator reviewing the change.', expect: 'Two lines reading ALTER SYSTEM, then a restart with no error.', code: `sudo apt-get install -y postgresql-16
sudo systemctl enable --now postgresql
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET listen_addresses = 'localhost';"
sudo -u postgres psql -X -v ON_ERROR_STOP=1 -c "ALTER SYSTEM SET password_encryption = 'scram-sha-256';"
sudo systemctl restart postgresql`}),
        step('Create a dedicated role and empty database', 'Server', `Creates the database login ${p.dbUser} and the empty database ${p.dbName}, owned by that login. Ownership lets the API create its tables (section 6). The login has no rights over other databases or users. The final command asks for the new password on screen, so it never appears in shell history.`, {watch: 'Run this once for a fresh installation. Choose a long, unique password and store it in the customer password manager. You will type it again in section 4.', expect: 'CREATE ROLE, CREATE DATABASE, REVOKE, GRANT, then two password prompts.', code: `sudo -u postgres psql -X -v ON_ERROR_STOP=1 <<'CUSTOMER_DB_SQL'
CREATE ROLE ${p.dbUser} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
CREATE DATABASE ${p.dbName} OWNER ${p.dbUser} ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE ${p.dbName} FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE ${p.dbName} TO ${p.dbUser};
CUSTOMER_DB_SQL
sudo -u postgres psql -X -c ${sh('\\password ' + p.dbUser)}`}),
        step('Require a password for the application login', 'Server', `pg_hba.conf is the file where PostgreSQL decides who may connect and how. This script finds the active file, checks whether the two rules for ${p.dbUser} already exist, and appends them only if they are missing. It keeps a dated backup, prints the difference between old and new file, reloads PostgreSQL and lists the rules PostgreSQL actually loaded. The last command logs in as the application role with the password you chose.`, {watch: 'PostgreSQL uses the first matching line in pg_hba.conf. A fresh Ubuntu 24.04 install already uses scram-sha-256 for 127.0.0.1 and ::1, so the appended lines are a safety net. If the printed rules show "trust" or "md5" for those addresses above your new lines, ask the database administrator before going on. The postgres administrator line ("local ... peer") must stay.', expect: 'A diff with two added host lines (or "already present"), a table of rules including scram-sha-256 for ' + p.dbUser + ', and one row showing ' + p.dbName + ' and ' + p.dbUser + '.', code: hbaCommand})
      ] : [
        step('Provision the managed database', null, 'Create a PostgreSQL 16 instance with the cloud provider. Turn on private networking, automated backups and point-in-time recovery. Allow connections only from the application server or its private network. Ask for a database owner role without superuser, CREATEDB, CREATEROLE or replication rights.', {watch: 'If you must use an existing instance of another major version, test the release against that version first and install the matching client tools on the server. Ask the database administrator to create the database and role if the provider restricts those commands.'}),
        step('Create the role and database as the administrator', 'Database admin', `Run this SQL once in a psql session signed in as the managed database administrator. It creates the login ${p.dbUser}, asks for its password on screen, creates the empty database ${p.dbName} owned by that login and removes default access for everyone else.`, {watch: 'The \\password line prompts for the password. Never put the password into this page, a chat message or a command line.', expect: 'CREATE ROLE, two password prompts, CREATE DATABASE, REVOKE, GRANT.', code: `CREATE ROLE ${p.dbUser} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
\\password ${p.dbUser}
CREATE DATABASE ${p.dbName} OWNER ${p.dbUser} ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE ${p.dbName} FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE ${p.dbName} TO ${p.dbUser};`, language: 'sql'}),
        step('Validate TLS and access', 'Server', (p.dbRootCert ? `Download the provider's CA certificate (the public file that proves the database server's identity) from the provider's official documentation and save it at ${p.dbRootCert}. It must be readable by ${svc} and by the SSH operator who runs psql and backups (for example under /etc/ssl/certs with mode 0644). It contains no private key. ` : 'This recipe expects the provider certificate to chain to the system CA store on the server. If the provider uses a private CA, go back to the wizard and set the root certificate path. ') + 'The commands below connect from the application server, print the database identity and confirm the connection is encrypted.', {watch: 'The DNS hostname you connect to must match the certificate. The API uses SSL Mode VerifyFull and psql uses verify-full. Never set Trust Server Certificate=true to skip verification. Install PostgreSQL client tools of the same major version as the managed server before running backups.', expect: 'One row with the database name, the role name and the PostgreSQL version, then one row where ssl is t (true).', code: `${dbEnv}
psql -X -W -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user, version();'
psql -X -W -v ON_ERROR_STOP=1 -c 'SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();'`})
      ], links: [link('PostgreSQL: SCRAM and password authentication', 'https://www.postgresql.org/docs/16/auth-password.html'), link('PostgreSQL: pg_hba.conf', 'https://www.postgresql.org/docs/16/auth-pg-hba-conf.html'), link('Npgsql: verified TLS', 'https://www.npgsql.org/doc/security.html')]},
      {id: 'server-secrets', title: '4. Save server-only application settings', summary: `The API reads its settings from a JSON file. On the server that file is ${overlay}; this guide calls it the "overlay". It holds the database connection string, the JWT signing key (the secret that signs login tokens), the Hoppa platform key and the email provider key. A script creates the file for you and asks for each secret on screen, so no secret is ever pasted into this page.`, outline: ['Collect the Hoppa and SendGrid values you will be asked for.', 'Run the setup script once; it writes the protected overlay.', 'Know the environment-variable names that override the file.', 'Understand which product features start disabled.'], steps: [
        step('Complete provider and email onboarding first', null, 'The script in the next step asks for: the Hoppa platform base URL, the company API key, the Hoppa webhook signing secret, the SumSub webhook signing secret, a verified SendGrid sender address and the SendGrid API key. Get the Hoppa values from your Hoppa contact. Get the SendGrid values from the customer\'s SendGrid account after the sender domain or address has been verified there.', {watch: 'If a SumSub webhook secret has not been agreed yet, enter a long random text now and keep the SumSub callback unregistered until it is ready. Check with your Hoppa contact which products (accounts, cards, KYC) are enabled for your company.'}),
        step('Create the protected Production overlay', 'Server', `Runs a small Python script as root. It writes ${overlay} with permissions 0640 (readable only by root and the ${svc} group), generates a fresh random JWT signing key and asks for each secret with a hidden prompt. Brand color, support email and legal entity are prefilled from this wizard; only missing details are asked.`, {watch: 'Run it once. If the file already exists the script stops instead of overwriting. Later edits go through "sudoedit ' + overlay + '". Backend branding is set here as well because the API serves its own branding endpoint, independent of the compiled app JSON.', expect: 'Prompts for each value, then "Customer configuration saved. No secrets were printed."', code: configCommand}),
        step('Know the equivalent environment keys', null, 'Every setting in the overlay can also be given as an environment variable, with two underscores instead of a colon. Examples: ConnectionStrings__NeoBankingDb, Jwt__SigningKey, Jwt__Issuer, Jwt__Audience, Company__InstallationId, Company__Name, Company__BrandName, Cors__AllowedOrigins__0, Cors__AllowedOrigins__1, Hoppa__BaseUrl, Hoppa__ApiKey, Hoppa__WebhookSecret, Hoppa__SumSubWebhookSecret, Email__SendGrid__ApiKey, SeedAdmin__Email and SeedAdmin__Password.', {watch: 'Environment values win over the JSON file. A forgotten environment variable can silently override the overlay. SeedAdmin values are only passed to the explicit migration command in section 6; they are never stored in the overlay.'}),
        step('Keep features deliberate', null, 'The generated overlay starts with every optional product switched off: referrals, vouchers, account claiming, exchange, wallet outflows, EqualsMoney and business onboarding. Push notifications and market data also stay off until their own credentials exist. Turn each one on in the overlay (Company:Features) only after the provider setup and the customer acceptance test for that product.', {watch: 'The branding JSON compiled into the app cannot enable backend features. The app shows a feature only when the API reports it as enabled.'})
      ]},
      {id: 'build-artifacts', title: '5. Build one reviewed release', summary: 'A release is one folder that contains the compiled API, the built admin website and the built web app, all from the same Git commit. You build it on your laptop (or a CI machine), pack it into one archive with a checksum and upload it. The server never compiles anything; it only runs what you upload.', outline: ['Install the build tools on your laptop.', 'Clone the customer repository and add the exported brand folder.', 'Build API, admin and app into one release folder and pack it.', 'Upload the archive and its checksum to the server.'], steps: [
        step('Install build tools', 'Laptop', 'You need: the .NET 10 SDK, Node.js 24 LTS with npm, Python 3.10 or newer with venv, and the Flutter version tested for this repository (3.44.2 with Dart 3.12.2). On an Ubuntu build machine, apt can install dotnet-sdk-10.0, python3-venv, git, curl, unzip and xz-utils. Install Node and Flutter with their official guides.', {watch: 'Node and Flutter are build tools only; they are not installed on the production server.', expect: 'node --version prints v24.x, dotnet --version prints 10.x and flutter --version prints 3.44.x.'}),
        step('Use the customer repository and the exported brand bundle', 'Laptop', `Clones the customer-owned repository into a folder named ${id}-source. Then you extract the handoff ZIP's config/ folder into mobile_flutter/config/${id}/ so that the JSON lives at mobile_flutter/config/${id}/brand.json next to its assets. The Python lines create a small isolated Python environment for the branding tool and validate the configuration without changing files.`, {watch: 'Keep each customer in its own checkout. Commit the configuration and assets before building so the release can be reproduced later.', expect: 'The --check command prints no errors. git status --short shows the added config files until you commit them.', code: `git clone ${sh(p.repoUrl)} ${sh(id + '-source')}
cd ${sh(id + '-source')}
# Save the exported JSON and its referenced assets here before continuing.
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r scripts/branding/requirements.txt
export BRANDING_PYTHON="$PWD/.venv/bin/python"
"$BRANDING_PYTHON" scripts/prepare-mobile-brand.py ${sh('mobile_flutter/config/' + id + '/brand.json')} --check
# Review and commit the intended customer config/assets before building.
git status --short`}),
        step('Build PWA, admin and API together', 'Laptop', `Creates a release folder named after the date and the Git commit. Builds the web app with the branded build wrapper, copies the generated logo into the admin website, builds the admin with the customer API address compiled in, publishes the API in Release mode and removes every appsettings*.json from it (production settings come only from the server overlay). Finally it packs everything into one .tar.gz archive and writes a SHA-256 checksum file next to it.`, {watch: `The API address is compiled into both browser apps; a different domain means a rebuild. No API keys belong in VITE_ variables or Flutter defines. The brand JSON does not yet restyle the admin's full color theme; see admin_vue/src/styles.css and admin_vue/src/main.ts for that. Open the archive and confirm it contains no credentials or signing files.`, expect: 'A file like 20260915T120000Z-abcdef123456.tar.gz and a matching .sha256 file in the repository root.', code: `set -euo pipefail
release="$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --short=12 HEAD)"
mkdir -p "artifacts/$release/api" "artifacts/$release/admin" "artifacts/$release/app"
./scripts/build-mobile-branded.sh web ${sh('mobile_flutter/config/' + id + '/brand.json')} --release --no-wasm-dry-run
cp -R mobile_flutter/build/web/. "artifacts/$release/app/"
cp mobile_flutter/build/web/branding/logo.png admin_vue/public/customer-logo.png
(
  cd admin_vue
  npm ci
  VITE_BACKEND_API_BASE_URL=${sh(apiUrl)} VITE_APP_NAME=${sh(p.appName)} VITE_APP_LOGO='/customer-logo.png' npm run build
)
cp -R admin_vue/dist/. "artifacts/$release/admin/"
dotnet restore backend/src/NeoBanking.Api/NeoBanking.Api.csproj
dotnet publish backend/src/NeoBanking.Api/NeoBanking.Api.csproj -c Release --no-restore -o "$PWD/artifacts/$release/api"
# Configuration for production is supplied only on the server.
find "artifacts/$release/api" -maxdepth 1 -name 'appsettings*.json' -delete
printf '%s\\n' "$(git rev-parse HEAD)" > "artifacts/$release/SOURCE_COMMIT"
cp ${sh('mobile_flutter/config/' + id + '/brand.json')} "artifacts/$release/brand.json"
# Review the archive contents; it must contain no customer credentials or signing files.
tar -C artifacts -czf "$release.tar.gz" "$release"
shasum -a 256 "$release.tar.gz" > "$release.tar.gz.sha256"`}),
        step('Upload the tested archive', 'Laptop', 'Copies the archive and its checksum file into the home folder of your SSH user on the server. Replace CUSTOMER_SSH_USER and CUSTOMER_SERVER_IP as in section 2.', {watch: 'Keep the archive and the recorded source commit. You need them for updates and for rolling back (section 11).', expect: 'scp prints a progress line for each of the two files.', code: `scp "$release.tar.gz" "$release.tar.gz.sha256" CUSTOMER_SSH_USER@CUSTOMER_SERVER_IP:~/`})
      ], links: [link('Node.js: supported releases', 'https://nodejs.org/en/about/previous-releases'), link('Node.js: installation', 'https://nodejs.org/en/download'), link('Flutter: installation', 'https://docs.flutter.dev/install'), link('Vite 8: Node requirements', 'https://vite.dev/blog/announcing-vite8')]},
      {id: 'release-stage', title: '6. Stage the server release', summary: `"Staging" means unpacking the uploaded archive into its own folder under ${root}/releases without starting it yet. You then link the overlay into it, create the database tables (a "migration") and create the first administrator account. The API starts only in section 7.`, outline: ['Verify the checksum and unpack the archive into a new release folder.', 'Run the migration with the first administrator prompt.', 'Confirm the migration table in the database.'], steps: [
        step('Verify and extract', 'Server', `Asks for the release ID (the archive filename without .tar.gz), checks its format, verifies the checksum, unpacks the archive under ${root}/releases and makes the files read-only for the service user. It then links the overlay from ${cfg} into the release folder so the API finds its settings.`, {watch: 'The format check refuses anything that is not a release ID from section 5. An existing release folder is never overwritten. Only unpack archives from your own reviewed build.', expect: 'The line "<release>.tar.gz: OK" from the checksum test and no other output.', code: `set -euo pipefail
read -r -p 'Uploaded release ID: ' release
[[ "$release" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]] || { echo 'Invalid release ID' >&2; exit 1; }
sha256sum -c "$release.tar.gz.sha256"
sudo test ! -e ${sh(root + '/releases')}/"$release"
sudo tar --no-same-owner -xzf "$release.tar.gz" -C ${sh(root + '/releases')}
sudo chown -R root:root ${sh(root + '/releases')}/"$release"
sudo chmod -R a+rX ${sh(root + '/releases')}/"$release"
sudo test -s ${sh(overlay)}
sudo ln -s ${sh(overlay)} ${sh(root + '/releases')}/"$release/api/appsettings.Production.json"
sudo -u ${sh(svc)} test -r ${sh(root + '/releases')}/"$release/api/appsettings.Production.json"`}),
        step('Apply migrations and seed the first admin', 'Server', 'A migration creates or updates the database tables. This Python wrapper asks for the first administrator email and password on screen, switches to the service user and starts the API once with the --migrate-and-seed flag. The API creates all tables and the admin account, prints one line and exits. The password is hashed by the application; it is not written to the overlay.', {watch: 'Run this before the first start. Running it again with a password changes that admin\'s password. Store the administrator password in the customer password manager before you close the session. No PostgreSQL extension is needed.', expect: '"Database migrated and admin account seeded for <email>."', code: `sudo python3 - "$release" <<'CUSTOMER_MIGRATION_PY'
import getpass, json, os, pwd, re, sys
release = sys.argv[1]
if not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}', release):
    raise SystemExit('Invalid release ID')
with open(${py(overlay)}) as source:
    config = json.load(source)
if not config['ConnectionStrings']['NeoBankingDb'] or len(config['Jwt']['SigningKey']) < 32:
    raise SystemExit('Configure customer DB and JWT settings first')
with open('/dev/tty', 'r+') as tty:
    tty.write('First admin email: '); tty.flush(); email = tty.readline().strip()
password = getpass.getpass('First admin password (unique, at least 16 characters): ')
if '@' not in email or len(password) < 16:
    raise SystemExit('Valid email and a password of at least 16 characters required')
env = {'PATH': '/usr/bin:/bin', 'HOME': '/var/lib/${svc}', 'ASPNETCORE_ENVIRONMENT': 'Production', 'SeedAdmin__Email': email, 'SeedAdmin__Password': password, 'SeedAdmin__DisplayName': 'Customer administrator'}
account = pwd.getpwnam(${py(svc)})
os.chdir(${py(root + '/releases/')} + release + '/api')
os.setgroups([account.pw_gid]); os.setgid(account.pw_gid); os.setuid(account.pw_uid)
os.execve('/usr/bin/dotnet', ['/usr/bin/dotnet', 'NeoBanking.Api.dll', '--migrate-and-seed'], env)
CUSTOMER_MIGRATION_PY`}),
        step('Check the database migration result', 'Server', 'Connects to the customer database as the application role and counts the rows in the migration history table. That table lists every migration the API has applied.', {watch: 'This check reads the database. It is separate from the /health address of the API, which only proves the process is running.', expect: 'One row with migration_count greater than 0.', code: `${dbEnv}
psql -X -W -v ON_ERROR_STOP=1 -c 'SELECT count(*) AS migration_count FROM public."__EFMigrationsHistory";'`})
      ]},
      {id: 'service', title: '7. Start the API through systemd', summary: 'systemd is the part of Ubuntu that starts programs at boot and restarts them when they crash. You describe the API in a "unit file", then activate the staged release by pointing a link named "current" at it. The API listens only on 127.0.0.1:5300; nginx (section 8) is the only thing the public reaches.', outline: ['Install the unit file that describes how to run the API.', 'Point the "current" link at the release, start the service and check /health.'], steps: [
        step('Install the service unit', 'Server', `Writes /etc/systemd/system/${svc}.service and tells systemd to reload its files. The unit runs the API as the ${svc} user, restarts it on failure and forbids it from writing outside /var/lib/${svc}.`, {watch: 'This starts only the API. Do not also start NeoBanking.Workers unless a reviewed requirement asks for it; the API already runs its own background services. If port 5300 is taken on this server, change it consistently in the unit, the nginx file and the health checks.', expect: 'No output.', code: `sudo tee /etc/systemd/system/${svc}.service > /dev/null <<'CUSTOMER_SERVICE_UNIT'
${unit}
CUSTOMER_SERVICE_UNIT
sudo systemctl daemon-reload`}),
        step('Activate the initial release', 'Server', `Creates the link ${root}/current pointing at the staged release, enables the service at boot, starts it, waits for the local health address to answer and prints the last 60 log lines.`, {watch: 'This is for the very first start; it refuses to run if a "current" link already exists. Later releases use section 11. If the curl line fails, read the journal output before doing anything else (see Troubleshooting).', expect: 'systemctl status shows "active (running)". curl prints {"status":"Healthy",...}.', code: `sudo test ! -e ${sh(root + '/current')}
sudo ln -s ${sh(root + '/releases')}/"$release" ${sh(root + '/current')}
sudo systemctl enable --now ${sh(svc)}
sudo systemctl status ${sh(svc)} --no-pager
curl --fail --retry 10 --retry-connrefused --retry-delay 2 http://127.0.0.1:5300/health
sudo journalctl -u ${sh(svc)} -n 60 --no-pager`})
      ]},
      {id: 'nginx-tls', title: '8. Publish nginx and HTTPS', summary: 'nginx is the public web server. It serves the web app and admin files directly and forwards API requests to the local API port. Certbot then requests free HTTPS certificates from Let\'s Encrypt for the three hostnames and configures automatic renewal.', outline: ['Install the nginx configuration for the three hostnames.', 'Request HTTPS certificates with Certbot.', 'Understand which files browsers may cache.'], steps: [
        step('Install the customer virtual hosts', 'Server', `Writes one nginx file with three "server" blocks: the API domain forwards to 127.0.0.1:5300, the app domain serves ${root}/current/app and the admin domain serves ${root}/current/admin. It then enables the file, tests the syntax and reloads nginx.`, {watch: 'The configuration assumes browsers connect straight to nginx. If you later put a load balancer or CDN in front, configure trusted proxy addresses before changing the X-Forwarded-For header; the API uses the first forwarded address for rate limiting.', expect: '"syntax is ok" and "test is successful" from nginx -t.', code: `sudo tee /etc/nginx/sites-available/${id} > /dev/null <<'CUSTOMER_NGINX_CONFIG'
${nginx}
CUSTOMER_NGINX_CONFIG
sudo ln -s /etc/nginx/sites-available/${id} /etc/nginx/sites-enabled/${id}
sudo nginx -t
sudo systemctl reload nginx`}),
        step('Issue HTTPS certificates', 'Server', 'Installs Certbot as a snap package, requests one certificate covering the three hostnames, rewrites the nginx file to use HTTPS and redirect HTTP, then simulates a renewal to prove renewal will work.', {watch: 'DNS from section 2 must already point at this server and port 80 must be reachable, or issuance fails (see Troubleshooting). If Certbot is already installed another way, follow the official migration notes instead of keeping two installations. Enter the customer\'s certificate contact email when asked.', expect: '"Successfully received certificate" and, for the dry run, "Congratulations, all simulated renewals succeeded".', code: `sudo snap install --classic certbot
sudo /snap/bin/certbot --nginx --redirect -d ${sh(p.apiDomain)} -d ${sh(p.appDomain)} -d ${sh(p.adminDomain)}
sudo /snap/bin/certbot renew --dry-run
sudo nginx -t`}),
        step('Understand caching', null, 'The web app is a PWA (a website that installs like an app and keeps a copy of its files in the browser). The branded build wrapper gives the service worker a new version after every web build, and this nginx file tells browsers to re-check PWA files on every visit ("no-cache"). Admin files under /assets/ have unique names per build, so they may be cached for a year. Gzip compression is on.', {watch: 'Rebuild and redeploy whenever branding or the API address changes. If users still see an old version, follow "App shows an old version" in Troubleshooting.'})
      ], links: [link('nginx: reverse proxy headers', 'https://nginx.org/en/docs/http/ngx_http_proxy_module.html'), link('Certbot: nginx instructions', 'https://certbot.eff.org/instructions?os=snap&ws=nginx')]},
      {id: 'acceptance', title: '9. Verify the customer experience', summary: 'Now you check the installation the way a customer would: from outside the server, over HTTPS, in a browser. An HTTP 200 from /health means the process responds; it does not prove database, email or provider readiness. That is why this section also has a manual acceptance test.', outline: ['Check HTTPS and browser permissions (CORS) from your laptop.', 'Walk through registration, login, email and branding by hand.', 'Register the webhook addresses with Hoppa and SumSub.'], steps: [
        step('Check HTTPS and both browser origins', 'Laptop', 'Requests the health and branding addresses over HTTPS, checks that both websites answer, and sends the "preflight" request a browser sends before calling the API from another domain. That preflight must be allowed for the app and admin domains (CORS).', {watch: 'Run these from a machine outside the server. The CORS response must contain the exact Origin you sent. Then open both websites and confirm in the browser developer tools that requests go only to the customer API domain.', expect: 'Each curl ends without error. The OPTIONS responses contain Access-Control-Allow-Origin with the requested domain.', code: `curl --fail ${sh(apiUrl + '/health')}
curl --fail ${sh(apiUrl + '/api/v1/branding')}
curl --fail --head ${sh(appUrl + '/')}
curl --fail --head ${sh(adminUrl + '/')}
curl --fail -i -X OPTIONS ${sh(apiUrl + '/api/v1/branding')} -H ${sh('Origin: ' + appUrl)} -H 'Access-Control-Request-Method: GET'
curl --fail -i -X OPTIONS ${sh(apiUrl + '/api/v1/branding')} -H ${sh('Origin: ' + adminUrl)} -H 'Access-Control-Request-Method: GET'`}),
        step('Complete an acceptance test', null, 'Sign in to the admin website with the seeded administrator. In the app: register a new customer, receive the verification email, log in, reset the password and log out. Check logo, splash screen, loader, fonts, light and dark mode, icons, support links and legal text on desktop and mobile browsers. Install the PWA on a phone, then deploy one small update and confirm the phone receives it.', {watch: 'Use the provider\'s approved test procedure for account, card and KYC callbacks before enabling real customer transactions. Check with your Hoppa contact for test accounts.'}),
        step('Register webhook destinations', null, `A webhook is an address the provider calls to tell your API about events (a card was issued, a KYC check finished). Register ${apiUrl}/api/v1/webhooks/hoppa with Hoppa and, if used, ${apiUrl}/api/v1/webhooks/sumsub with SumSub. Use exactly the signing secrets stored in the overlay in section 4.`, {watch: 'Send a signed test event from the provider and confirm the resulting change in the admin website. An unsigned request answered with 401 is expected; it is not a complete test.'})
      ]},
      {id: 'backups', title: '10. Back up and practise recovery', summary: 'A backup is only useful if someone has restored it before. This section takes a portable database backup, explains what else to keep, and restores the backup into a separate throw-away database to prove the procedure works.', outline: ['Take a database backup with pg_dump and record its checksum.', 'Assign monitoring for the service, disk, certificates and backups.', 'Copy the full recovery set to encrypted off-server storage.', 'Restore into an isolated test database and check it.'], steps: [
        step('Take a portable database backup', 'Server', 'Creates a folder in your home directory, writes a compressed PostgreSQL "custom format" backup of the customer database, lists its contents and stores a checksum. The backup contains tables and data; it does not contain database roles.', {watch: 'Use pg_dump with the same major version as the server, or newer. The -W flag asks for the role password on screen. For unattended nightly backups use the customer secret manager or a 0600 PostgreSQL password file, never a password on the command line. Arrange retention in the customer backup system.', expect: 'A password prompt, then three new files ending in .dump, .dump.contents and .dump.sha256.', code: `${dbEnv}
umask 077
mkdir -p "$HOME/customer-backups"
backup="$HOME/customer-backups/${p.dbName}-$(date -u +%Y%m%dT%H%M%SZ).dump"
pg_dump -W --format=custom --no-owner --no-acl --file="$backup"
pg_restore --list "$backup" > "$backup.contents"
sha256sum "$backup" > "$backup.sha256"`}),
        step('Monitor routine operation', null, 'Name one person who receives alerts for: external HTTPS and health checks, API errors, database and disk capacity, certificate renewal and backup job failures.', {watch: 'Alert on missing backups, not only failed ones. A backup file on disk is not proof that it can be restored. Repeat the restore drill after significant schema or backup-system changes.'}),
        step('Protect the complete recovery set', null, `Copy the database dump to encrypted, customer-owned storage outside this server. Also keep: ${overlay}, provider and Firebase credentials, the nginx and systemd files, the DNS records, the source commit, the brand assets and the tested release archive. Managed databases should also have provider backups and point-in-time recovery enabled.`, {watch: 'Agree retention and recovery targets (how much data may be lost, how long recovery may take) with the customer and write them down.'}),
        step('Restore into an isolated database', p.dbMode === 'local' ? 'Server' : 'Database admin', `Creates a NEW empty database named ${p.dbName}_restore_test owned by the application role, restores the backup into it and counts the migration rows. PGDATABASE is switched to the drill database only for these commands and then switched back.`, {watch: 'Never point this at the production database. For managed PostgreSQL, have the provider administrator create the drill database first, then run the remaining lines on the application server. Do not start an API against restored data with real provider keys or background workers: that could repeat real external actions.', expect: 'pg_restore finishes without error and migration_count matches the production value from section 6.', code: `${p.dbMode === 'local' ? 'sudo -u postgres createdb --owner=' + sh(p.dbUser) + ' ' + sh(p.dbName + '_restore_test') + '\n' : '# Have your managed DB administrator create ' + p.dbName + '_restore_test first.\n'}${dbEnv}
export PGDATABASE=${sh(p.dbName + '_restore_test')}
pg_restore -W --exit-on-error --no-owner --no-acl --dbname="$PGDATABASE" "$backup"
psql -X -W -v ON_ERROR_STOP=1 -c 'SELECT count(*) AS migration_count FROM public."__EFMigrationsHistory";'
# Record the restore duration and validate expected records before cleaning up.
export PGDATABASE=${sh(p.dbName)}`})
      ], links: [link('PostgreSQL: backup approaches', 'https://www.postgresql.org/docs/16/backup.html'), link('PostgreSQL: pg_dump', 'https://www.postgresql.org/docs/16/app-pgdump.html'), link('PostgreSQL: pg_restore', 'https://www.postgresql.org/docs/16/app-pgrestore.html')]},
      {id: 'updates', title: '11. Update and roll back deliberately', summary: `Every release keeps its own folder under ${root}/releases. Updating means staging a new folder (section 6) and moving the "current" link. Rolling back means moving the link back. Application files can always be rolled back this way; a database migration cannot, so you back up first.`, outline: ['Build, upload and stage the next release; back up the database first.', 'Apply the new release\'s migrations if it has any.', 'Switch the "current" link with an automatic rollback if the health check fails.', 'Bring in functional fixes from the upstream repository one commit at a time.'], steps: [
        step('Prepare the next release', null, 'Build all three components from one reviewed commit (section 5), upload, verify and stage it (section 6, first step). Take and verify a fresh backup (section 10) before any migration.', {watch: 'Review the release\'s database changes for compatibility with both the old and the new code. For an incompatible change, schedule a maintenance window and stop the API before migrating. Allow only one person or process to deploy at a time.'}),
        step('Apply reviewed migrations to an existing customer database', 'Server', 'Runs the migration command from inside the staged release folder as the service user, with a clean environment. Without a SeedAdmin password the application keeps the existing administrator untouched.', {watch: 'Use this only when the release includes approved migrations. A brand-new database still needs the first-admin prompt from section 6.', expect: '"Database migrated and admin account seeded for ..." or a short message that the existing admin was kept.', code: `[[ "$release" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]] || exit 1
(
  cd ${sh(root + '/releases')}/"$release/api"
  sudo -u ${sh(svc)} env -i PATH=/usr/bin:/bin HOME=/var/lib/${svc} ASPNETCORE_ENVIRONMENT=Production /usr/bin/dotnet NeoBanking.Api.dll --migrate-and-seed
)`}),
        step('Activate the staged release with a saved rollback target', 'Server', 'Remembers the currently active release, swaps the "current" link to the new release in one atomic move, restarts the API and waits for /health. If the restart or the health check fails, the script swaps the link back, restarts the previous release and exits with an error.', {watch: 'One link selects API, admin and web app together. The API restarts, so this is a short interruption, not a zero-downtime rollout. The automatic rollback restores the application only; it cannot undo a database migration. Continue with the acceptance checks from section 9 afterwards.', expect: '"Previous release retained: /opt/.../releases/<old id>" on success.', code: `set -euo pipefail
[[ "$release" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]] || exit 1
previous="$(readlink -f ${sh(root + '/current')})"
case "$previous" in ${root}/releases/*) ;; *) echo 'Unexpected previous release' >&2; exit 1;; esac
sudo test -r ${sh(root + '/releases')}/"$release/api/appsettings.Production.json"
sudo ln -s ${sh(root + '/releases')}/"$release" ${sh(root + '/.current-next')}
sudo mv -Tf ${sh(root + '/.current-next')} ${sh(root + '/current')}
if ! sudo systemctl restart ${sh(svc)} || ! curl --fail --retry 10 --retry-connrefused --retry-delay 2 http://127.0.0.1:5300/health; then
  sudo ln -s "$previous" ${sh(root + '/.current-rollback')}
  sudo mv -Tf ${sh(root + '/.current-rollback')} ${sh(root + '/current')}
  sudo systemctl restart ${sh(svc)}
  curl --fail --retry 10 --retry-connrefused --retry-delay 2 http://127.0.0.1:5300/health
  echo 'Previous application restored; verify database compatibility.' >&2
  exit 1
fi
printf 'Previous release retained: %s\\n' "$previous"`}),
        step('Share functional fixes', null, 'Keep customer branding and assets in their own configuration files. Bring bug fixes from the upstream repository into the customer repository one focused commit at a time (git cherry-pick), test them against the customer configuration and provider setup, then release normally.', {watch: 'A Git copy does not update itself. Never merge a whole upstream branch blindly into a customer installation; it may carry another customer\'s branding or deployment settings.'})
      ]},
      {id: 'native-provider', title: '12. Native apps and ownership handoff', summary: 'A web build does not create app store accounts, signing identities or provider entitlements. This section lists what the customer must own for Android and iOS releases and what to hand over at the end.', outline: ['Android: application ID, Play Console account, upload signing key.', 'iOS: bundle ID, Apple Developer account, macOS with Xcode for builds.', 'Optional Firebase push setup.', 'Final ownership checklist.'], steps: [
        step('Android ownership', null, 'The customer chooses a permanent Android application ID and owns the Google Play developer account, the app entry and the upload signing key. Build with ./scripts/build-mobile-branded.sh appbundle <customer-config.json> --release only after release signing is configured.', {watch: 'Keep the keystore and its passwords in the customer\'s signing system. Complete Play\'s privacy and data-safety forms. Test on physical devices.'}),
        step('iOS ownership', null, 'The customer chooses a permanent iOS bundle ID and owns the Apple Developer and App Store Connect app. iOS builds need macOS with Xcode, an assigned team, provisioning profiles and signing certificates. Build with ./scripts/build-mobile-branded.sh ipa <customer-config.json> --release after those exist.', {watch: 'Review display names, privacy information, associated domains and push capabilities before submission.'}),
        step('Optional Firebase push', null, 'If push notifications are needed, create the customer\'s Firebase project and register Android and iOS apps with the same IDs as above. Supply the public client files through the brand configuration. On the API server, store the Firebase Admin service account file, set PushNotifications__Enabled, FirebaseProjectId and ServiceAccountPath in the overlay and let the service user read the file. Upload the customer\'s APNs key in Firebase for iOS and test on real devices.', {watch: 'Never include a Firebase Admin private key in the exported JSON or app assets. Only the client files (google-services.json, GoogleService-Info.plist) belong in the app.'}),
        step('Final ownership checklist', null, 'Hand over: the customer repository, the exported brand JSON and assets, compiled app artifacts, the owners of server, DNS and cloud accounts, provider and webhook contacts, the database recovery procedure, signing and store owners, monitoring and support ownership. Record which features passed acceptance and which stay disabled.', {watch: 'Full admin recoloring and provider-hosted KYC or payment screens are separate from the Flutter branding JSON.'})
      ]},
      {id: 'troubleshooting', title: '13. Troubleshooting', summary: 'The most common problems on a new installation, each with the command that shows the cause. Read the output slowly; the first error line is usually the real one.', outline: ['API service fails to start: read the journal.', 'nginx answers 502 Bad Gateway: the API is not listening.', 'Certbot fails: DNS or port 80.', 'Migration cannot connect: the connection string.', 'Browser shows a CORS error: Cors:AllowedOrigins.', 'App shows an old version: service worker and caching.'], steps: [
        step('API service fails to start', 'Server', `Shows the service state and the last 100 log lines of ${svc}. The journal is where systemd keeps program output.`, {watch: 'Typical causes: Jwt:SigningKey shorter than 32 characters (the API refuses to start outside Development), an empty or wrong connection string, a missing appsettings.Production.json link in the release folder, or port 5300 already in use. Fix the overlay with "sudoedit ' + overlay + '" and run "sudo systemctl restart ' + svc + '".', expect: 'An "active (running)" state, or an exception message near the end of the journal that names the missing setting.', code: `sudo systemctl status ${sh(svc)} --no-pager
sudo journalctl -u ${sh(svc)} -n 100 --no-pager
sudo ss -ltnp | grep ':5300 ' || echo 'Nothing is listening on 5300'`}),
        step('nginx answers 502 Bad Gateway', 'Server', 'A 502 means nginx is running but could not reach the API on 127.0.0.1:5300. The first command asks the API directly, bypassing nginx. The others show the service state and the nginx error log.', {watch: 'If the direct curl works but the public address does not, check the proxy_pass port in /etc/nginx/sites-available/' + id + ' and run "sudo nginx -t". If the direct curl fails, follow "API service fails to start" above.', expect: 'curl prints {"status":"Healthy",...}. The nginx error log has no new "connect() failed" lines.', code: `curl -i http://127.0.0.1:5300/health
sudo systemctl status ${sh(svc)} --no-pager
sudo tail -n 50 /var/log/nginx/error.log`}),
        step('Certbot fails on DNS or port 80', 'Server', 'Let\'s Encrypt must reach each hostname on port 80 from the internet. The commands print the address each hostname resolves to, the firewall state, what is listening on port 80 and the nginx syntax check.', {watch: 'Each hostname must resolve to this server\'s public IP. A cloud firewall or security group can block port 80 even when ufw allows it. Fix DNS or the firewall, wait a few minutes, then run the certbot command from section 8 again.', expect: 'All three hostnames resolve to the public address shown in the hosting provider dashboard; ufw shows "Nginx Full" allowed; nginx is listening on :80.', code: `for name in ${sh(p.apiDomain)} ${sh(p.appDomain)} ${sh(p.adminDomain)}; do printf '%s -> ' "$name"; getent ahosts "$name" | awk '{print $1}' | sort -u | tr '\\n' ' '; echo; done
sudo ufw status
sudo ss -ltnp | grep ':80 ' || echo 'Nothing is listening on port 80'
sudo nginx -t`}),
        step('Migration cannot connect to the database', 'Server', 'Prints the non-secret parts of the connection string from the overlay (host, port, database, user, SSL mode) and whether a password is present. Then tries the same login with psql.', {watch: 'Compare host, port, database and role with section 3. A local recipe must use 127.0.0.1 and SSL Mode Disable; a managed recipe must use the certificate hostname and VerifyFull. If psql cannot log in either, the role password or the pg_hba.conf rules are wrong. Fix the overlay with sudoedit and rerun the migration step from section 6.', expect: 'The printed values match section 3, "Password set: yes", a SigningKey length of 32 or more, and one row from the psql login.', code: `${overlayInspect}
${dbEnv}
psql -X -W -v ON_ERROR_STOP=1 -c 'SELECT current_database(), current_user;'`}),
        step('Browser shows a CORS error', 'Server', `CORS is the browser rule that lets a website call an API on another domain only when the API allows that website's origin. The API allows the origins listed in Cors:AllowedOrigins in the overlay. This prints the current list and repeats the preflight check.`, {watch: `An origin is scheme plus host, with no path and no trailing slash: ${appUrl} and ${adminUrl}. After editing the overlay run "sudo systemctl restart ${svc}". On a laptop the API allows localhost origins automatically, only in Development.`, expect: 'The printed list contains both public origins. The curl response includes Access-Control-Allow-Origin: ' + appUrl + '.', code: `${overlayInspect}
curl -i -X OPTIONS ${sh(apiUrl + '/api/v1/branding')} -H ${sh('Origin: ' + appUrl)} -H 'Access-Control-Request-Method: GET'`}),
        step('App shows an old version', 'Server', 'The web app keeps a copy of itself in the browser through a service worker. After a deployment the browser must be told to re-check. These commands confirm that nginx sends "Cache-Control: no-cache" for the PWA files and that the current release really is the new one.', {watch: 'On the phone or laptop: close all tabs of the app, reopen it, or in Chrome open DevTools > Application > Service Workers > Unregister and reload. Always build the web app through ./scripts/build-mobile-branded.sh; it stamps a new service-worker version. If the Cache-Control header is missing, nginx is serving a different configuration file.', expect: 'Both curl outputs contain "Cache-Control: no-cache". The SOURCE_COMMIT matches the commit you built.', code: `curl -sI ${sh(appUrl + '/flutter_bootstrap.js')} | grep -i 'cache-control'
curl -sI ${sh(appUrl + '/index.html')} | grep -i 'cache-control'
readlink -f ${sh(root + '/current')}
cat ${sh(root + '/current/SOURCE_COMMIT')}`})
      ]},
      {id: 'glossary', title: '14. Glossary', summary: 'Short definitions of the terms used in this guide, in the order you meet them.', outline: [], steps: [], terms: [
        term('API', 'The .NET program that holds all business logic. The app and the admin website talk only to it. It talks to PostgreSQL and to the Hoppa platform.'),
        term('PWA', 'Progressive Web App. The customer app built for the browser. It can be installed on a phone from the browser and caches its own files.'),
        term('Admin website', 'The Vue website used by the customer\'s staff to manage users, cards, verification and email templates.'),
        term('Hoppa platform', 'The provider platform that actually holds accounts, cards and KYC state. Your API calls it with a company API key.'),
        term('SumSub', 'The identity-verification (KYC) provider used through Hoppa. It calls your API back with a signed webhook.'),
        term('SSH', 'Secure Shell. A terminal connection to the server over the network. All "Run on: Server" commands are typed inside an SSH session.'),
        term('sudo', 'Runs one command as the Linux administrator (root). Ubuntu asks for your password the first time.'),
        term('DNS / A record', 'DNS turns a name like api.example.com into an IP address. An A record is the entry that holds an IPv4 address; AAAA holds IPv6.'),
        term('ufw', 'Uncomplicated Firewall. The Ubuntu tool that decides which network ports accept connections.'),
        term('Loopback / 127.0.0.1', 'The address of the machine itself. A program listening on 127.0.0.1 is reachable only from that machine.'),
        term('nginx', 'The public web server. It serves static files and forwards API requests to the local API port (a "reverse proxy").'),
        term('systemd / unit file', 'The Ubuntu service manager and the text file that tells it how to run a program, as which user and what to do on failure.'),
        term('PostgreSQL', 'The database server. It stores users, cards, settings and the migration history.'),
        term('Role', 'A PostgreSQL login. The API uses a role that owns only the customer database.'),
        term('pg_hba.conf', 'The PostgreSQL file that lists who may connect, from where and with which authentication method.'),
        term('SCRAM (scram-sha-256)', 'The modern PostgreSQL password method. Passwords are never sent or stored in plain form.'),
        term('Connection string', 'One line of Host=..;Port=..;Database=..;Username=..;Password=.. that tells the API how to reach PostgreSQL.'),
        term('Migration', 'A scripted database change that creates or updates tables. The API applies them with the --migrate-and-seed flag.'),
        term('Seeded admin', 'The first administrator account, created during the migration command from SeedAdmin__Email and SeedAdmin__Password.'),
        term('Overlay', 'This guide\'s name for ' + overlay + ', the server-only settings file the API reads in Production.'),
        term('JWT / signing key', 'A login token the API issues after sign-in, and the secret used to sign it. Anyone with the key could forge logins, so it stays on the server.'),
        term('Environment variable', 'A named value given to a program when it starts, for example ASPNETCORE_ENVIRONMENT=Production. Two underscores stand for a colon in setting names.'),
        term('Release / release ID', 'One built folder with API, admin and app from one Git commit, named <date>-<commit>. Releases are never edited after upload.'),
        term('Symlink ("current")', 'A link that points at a folder. Moving ' + root + '/current to another release switches all three components at once.'),
        term('TLS / HTTPS certificate', 'The encryption for web traffic and the file that proves a domain belongs to this server. Certbot obtains it from Let\'s Encrypt.'),
        term('Certbot', 'The tool that requests and renews HTTPS certificates and edits the nginx file to use them.'),
        term('CORS', 'The browser rule that blocks a website from calling an API on another domain unless the API lists that website in Cors:AllowedOrigins.'),
        term('Webhook', 'An address on your API that a provider calls to report an event. Each call is signed with a shared secret.'),
        term('Service worker', 'A small script in the browser that caches the PWA. It must be updated (a new version) so users receive a new release.'),
        term('SendGrid', 'The email delivery service the API uses for verification and password-reset emails.'),
        term('pg_dump / pg_restore', 'The PostgreSQL tools that write a backup file and load it into a database.')
      ]}
    ];
    return sections;
  }

  global.CustomerServerGuide = Object.freeze({render, validate, WHERE, version: 2});
})(typeof window !== 'undefined' ? window : globalThis);
