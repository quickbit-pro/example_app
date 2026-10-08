import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import '../customer-guide/server-guide.js';

const guide = globalThis.CustomerServerGuide;
const local = {
  brandId: 'acme', appName: 'Acme', apiDomain: 'api.acme.example',
  appDomain: 'app.acme.example', adminDomain: 'admin.acme.example',
  dbMode: 'local', dbHost: '127.0.0.1', dbPort: 5432,
  dbName: 'acme_db', dbUser: 'acme_app', dbSslMode: 'Disable', dbRootCert: '',
  repoUrl: 'https://github.com/customer-org/customer-app.git',
};
const managed = {
  ...local, dbMode: 'managed', dbHost: 'postgres.private.acme.example',
  dbSslMode: 'VerifyFull', dbRootCert: '/etc/ssl/certs/acme-postgres-ca.pem',
};
const section = (sections, id) => sections.find(item => item.id === id);
const allSteps = sections => sections.flatMap(item => item.steps);
const settingsCommand = params => allSteps(guide.render(params)).find(item => item.code?.includes('CUSTOMER_CONFIG_PY')).code;
const embeddedPython = (code, marker) => code.split(`<<'${marker}'\n`)[1]?.split(`\n${marker}`)[0];
const settingsObject = code => {
  const line = code.split('\n').find(item => item.startsWith('settings = json.loads('));
  return JSON.parse(JSON.parse(line.slice('settings = json.loads('.length, -1)));
};

// These tests parse instructions only. They never run generated deployment commands.
function parses(command, args, input, label) {
  const result = spawnSync(command, args, {input, encoding: 'utf8', timeout: 10000});
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${label}: ${result.stderr}`);
}

test('local PostgreSQL guide isolates its database and uses customer paths', () => {
  assert.deepEqual(guide.validate(local), []);
  const sections = guide.render(local);
  const db = JSON.stringify(section(sections, 'database'));
  assert.match(db, /postgresql-16/);
  assert.match(db, /scram-sha-256/);
  assert.match(db, /NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION/);
  assert.match(db, /REVOKE ALL ON DATABASE acme_db FROM PUBLIC/);
  assert.match(db, /127\.0\.0\.1/);
  const service = JSON.stringify(section(sections, 'service'));
  assert.match(service, /app-acme/);
  assert.match(service, /\/opt\/acme\/current\/api/);
  assert.match(service, /127\.0\.0\.1:5300/);
  const config = settingsObject(settingsCommand(local));
  assert.equal(config.ConnectionStrings.NeoBankingDb, '');
  assert.equal(config.Jwt.SigningKey, '');
  assert.equal(config.Hoppa.ApiKey, '');
  assert.deepEqual(config.Cors.AllowedOrigins, ['https://app.acme.example', 'https://admin.acme.example']);
});

test('managed PostgreSQL guide requires verified TLS and an explicit CLI CA', () => {
  const sections = guide.render(managed);
  const db = JSON.stringify(section(sections, 'database'));
  assert.doesNotMatch(db, /apt-get install -y postgresql-16/);
  assert.match(db, /verify-full/);
  assert.match(db, /PGSSLROOTCERT/);
  assert.match(db, /\/etc\/ssl\/certs\/acme-postgres-ca\.pem/);
  const command = settingsCommand(managed);
  assert.match(command, /'SSL Mode': "VerifyFull"/);
  assert.match(command, /parts\['Root Certificate'\] = "\/etc\/ssl\/certs\/acme-postgres-ca.pem"/);
  assert.doesNotMatch(command, /Trust Server Certificate/);
  const withSystemCA = JSON.stringify(guide.render({...managed, dbRootCert: ''}));
  assert.match(withSystemCA, /\/etc\/ssl\/certs\/ca-certificates\.crt/);
});

test('wizard branding defaults are safely encoded and do not prompt twice', () => {
  const params = {
    ...local, appName: 'Acme “Pay”', legalEntity: `Acme's "Finance" $value \\ Ltd`,
    primaryColor: '#FF621a96', supportEmail: "customer's-support@acme.example",
    termsUrl: 'https://acme.example/terms?version=1', privacyUrl: 'https://acme.example/privacy',
  };
  const command = settingsCommand(params);
  const config = settingsObject(command);
  assert.equal(config.Company.Name, params.legalEntity);
  assert.equal(config.Company.BrandName, params.appName);
  assert.equal(config.Company.Branding.PrimaryColor, '#621A96');
  assert.equal(config.Company.Branding.SupportEmail, params.supportEmail);
  assert.equal(config.Company.Branding.TermsUrl, params.termsUrl);
  assert.equal(config.Company.Branding.PrivacyUrl, params.privacyUrl);
  for (const label of ['Customer legal company name', 'Brand primary color, for example #621A96', 'Customer support email', 'Published HTTPS terms URL', 'Published HTTPS privacy URL']) {
    assert.ok(!command.includes(`prompt('${label}')`), `unexpected repeated prompt: ${label}`);
  }
  assert.match(command, /secret\('Database role password created earlier'\)/);
  assert.match(command, /getpass\.getpass/);
});

test('missing optional branding details remain server-side prompts', () => {
  const command = settingsCommand(local);
  for (const label of ['Customer legal company name', 'Brand primary color, for example #621A96', 'Customer support email', 'Published HTTPS terms URL', 'Published HTTPS privacy URL']) {
    assert.ok(command.includes(`prompt('${label}')`), `missing prompt: ${label}`);
  }
});

test('unsafe command inputs and weaker database settings are rejected', () => {
  const cases = [
    {...local, brandId: '../bad'}, {...local, brandId: 'a'.repeat(25)},
    {...local, appName: 'bad\nname'}, {...local, apiDomain: 'example.com;whoami'},
    {...local, appDomain: local.apiDomain}, {...local, dbName: 'db;DROP DATABASE customer'},
    {...local, dbUser: '-postgres'}, {...local, dbPort: 0}, {...local, dbPort: '5432;true'},
    {...local, dbHost: '0.0.0.0'}, {...local, dbSslMode: 'Require'},
    {...managed, dbSslMode: 'Require'}, {...managed, dbHost: '127.0.0.1'},
    {...managed, dbRootCert: '/etc/../root/ca.pem'},
    {...local, repoUrl: 'https://username:password@github.com/customer/app.git'},
    {...local, repoUrl: 'https://github.com/customer/app.git?token=secret'},
    {...local, primaryColor: '#80621A96'}, {...local, primaryColor: 'red'},
    {...local, supportEmail: 'not-an-email'}, {...local, supportEmail: 'a@example.com\nnext'},
    {...local, legalEntity: 'bad\ncompany'}, {...local, termsUrl: 'javascript:alert(1)'},
    {...local, privacyUrl: 'https://secret:password@example.com/privacy'},
  ];
  for (const params of cases) {
    assert.ok(guide.validate(params).length > 0, `unexpected valid input: ${JSON.stringify(params)}`);
    assert.throws(() => guide.render(params));
  }
});

test('all local/managed generated Bash and embedded Python snippets parse without executing', () => {
  const variants = [local, managed, {
    ...managed, dbRootCert: '',
    appName: `A customer's "brand" $(untrusted) \\ <safe>`,
    primaryColor: '#336699', supportEmail: "customer's-support@acme.example",
    legalEntity: `Customer's "Legal" \\ Name`,
    termsUrl: 'https://acme.example/terms', privacyUrl: 'https://acme.example/privacy',
  }];
  for (const params of variants) {
    for (const item of allSteps(guide.render(params))) {
      if (!item.code) continue;
      if (item.language === 'bash') parses('bash', ['-n'], item.code, item.title);
      for (const marker of ['CUSTOMER_CONFIG_PY', 'CUSTOMER_MIGRATION_PY']) {
        const code = embeddedPython(item.code, marker);
        if (code) parses('python3', ['-c', 'import ast, sys; ast.parse(sys.stdin.read())'], code, marker);
      }
    }
  }
});

test('build and smoke checks match repository conventions', () => {
  const sections = guide.render(local);
  const build = JSON.stringify(section(sections, 'build-artifacts'));
  assert.match(build, /VITE_BACKEND_API_BASE_URL/);
  assert.doesNotMatch(build, /VITE_API_BASE_URL/);
  assert.match(build, /mobile_flutter\/config\/acme\/brand\.json/);
  assert.match(build, /appsettings\*\.json/);
  assert.match(JSON.stringify(section(sections, 'release-stage')), /public\.\\"__EFMigrationsHistory\\"/);
  const nginx = allSteps(sections).find(item => item.code?.includes('CUSTOMER_NGINX_CONFIG')).code;
  const pwaBlock = nginx.split('server_name app.acme.example;')[1].split('server {')[0];
  assert.match(pwaBlock, /no-cache/);
  assert.doesNotMatch(pwaBlock, /immutable/);
  assert.match(nginx, /proxy_set_header X-Forwarded-For \$remote_addr/);
  assert.match(JSON.stringify(section(sections, 'acceptance')), /does not prove database/);
});

// Structure for inexperienced readers: where each command runs, what it does, what to watch.
const appSource = readFileSync(new URL('../customer-guide/app.js', import.meta.url), 'utf8');

test('every command block says where it runs and every section has an overview and outline', () => {
  assert.deepEqual(guide.WHERE, ['Laptop', 'Server', 'Database admin']);
  for (const params of [local, managed]) {
    const sections = guide.render(params);
    for (const section of sections) {
      assert.ok(section.summary.length > 40, `${section.id}: summary`);
      assert.ok(Array.isArray(section.outline), `${section.id}: outline`);
      if (section.id !== 'glossary') assert.ok(section.outline.length > 0, `${section.id}: outline entries`);
      for (const item of section.steps) {
        assert.ok(item.title && item.text, `${section.id}: ${item.title}`);
        if (item.code) assert.ok(guide.WHERE.includes(item.where), `${section.id}: "${item.title}" has code without a where badge`);
        if (item.where) assert.ok(guide.WHERE.includes(item.where));
      }
    }
    const withCode = allSteps(sections).filter(item => item.code);
    assert.ok(withCode.some(item => item.where === 'Laptop'));
    assert.ok(withCode.some(item => item.where === 'Server'));
    assert.ok(withCode.filter(item => item.watch).length > withCode.length / 2, 'most command steps carry a Watch out line');
  }
  assert.equal(allSteps(guide.render(managed)).find(item => item.code?.includes('CREATE ROLE')).where, 'Database admin');
});

test('pg_hba.conf is changed by a checked, backed-up, diffed append instead of a manual edit', () => {
  const db = section(guide.render(local), 'database');
  const hba = db.steps.find(item => item.code?.includes('SHOW hba_file')).code;
  assert.doesNotMatch(hba, /sudoedit/);
  assert.match(hba, /grep -qxF "\$rule_v4" "\$hba" && sudo grep -qxF "\$rule_v6" "\$hba"/);
  assert.match(hba, /host  acme_db  acme_app  127\.0\.0\.1\/32  scram-sha-256/);
  assert.match(hba, /host  acme_db  acme_app  ::1\/128       scram-sha-256/);
  assert.match(hba, /sudo cp -p "\$hba" "\$backup"/);
  assert.match(hba, /sudo diff -u "\$backup" "\$hba"/);
  assert.match(hba, /pg_hba_file_rules/);
  assert.match(hba, /systemctl reload postgresql/);
  parses('bash', ['-n'], hba, 'pg_hba append script');
});

test('troubleshooting covers the common failures and the glossary defines the terms', () => {
  for (const params of [local, managed]) {
    const sections = guide.render(params);
    const troubleshooting = JSON.stringify(section(sections, 'troubleshooting'));
    for (const pattern of [/journalctl -u 'app-acme'/, /502 Bad Gateway/, /Certbot fails on DNS or port 80/, /ss -ltnp \| grep ':80 '/, /Migration cannot connect/, /ConnectionStrings/, /CORS/, /Cors:AllowedOrigins/, /App shows an old version/, /Service Workers/, /Cache-Control: no-cache/]) {
      assert.match(troubleshooting, pattern);
    }
    const glossary = section(sections, 'glossary');
    assert.ok(glossary.terms.length >= 20);
    const names = glossary.terms.map(item => item.term);
    for (const expected of ['API', 'PWA', 'nginx', 'PostgreSQL', 'Migration', 'Connection string', 'JWT / signing key', 'CORS', 'Webhook', 'Service worker', 'Certbot']) {
      assert.ok(names.includes(expected), `glossary term ${expected}`);
    }
    for (const item of glossary.terms) assert.ok(item.definition.length > 20, item.term);
    for (const item of allSteps(sections)) {
      const check = embeddedPython(item.code || '', 'CUSTOMER_CHECK_PY');
      if (check) parses('python3', ['-c', 'import ast, sys; ast.parse(sys.stdin.read())'], check, 'CUSTOMER_CHECK_PY');
    }
  }
});

test('internal deployment scripts, other customers and internal hosts are not mentioned', () => {
  const internal = /deploy-hoppa|prepare-hoppa-pwa|roks\.dev|internal Hoppa/;
  for (const params of [local, managed]) assert.doesNotMatch(JSON.stringify(guide.render(params)), internal);
  assert.doesNotMatch(appSource, internal);
  assert.match(appSource, /repoUrl: 'https:\/\/github\.com\/quickbit-pro\/example_app\.git'/);
  assert.deepEqual(guide.validate({...local, repoUrl: 'https://github.com/quickbit-pro/example_app.git'}), []);
});

test('the wizard renders where badges and the handoff README has a ten-step quick start', () => {
  assert.match(appSource, /function whereBadge\(where\)/);
  assert.match(appSource, /codeBlock\(item\.code, item\.where, item\.language\)/);
  assert.match(appSource, /\*\*Run on:\*\* \$\{item\.where\}/);
  assert.match(appSource, /## Quick start in 10 steps/);
  const quickStart = appSource.split('## Quick start in 10 steps')[1].split('## App build')[0];
  assert.deepEqual(quickStart.split('\n').filter(line => /^\d+\. /.test(line)).map(line => Number(line.split('.')[0])), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  for (const short of ['Before you start', 'Brand basics', 'Colors & type', 'Logos & launch', 'Connections', 'Run it on your laptop', 'Customize beyond branding', 'Server setup', 'Review & export']) {
    assert.ok(appSource.includes(`short: '${short}'`), `step ${short}`);
  }
  for (const fact of ['http://localhost:5188', 'http://localhost:5173', '--migrate-and-seed', 'appsettings.Local.json', 'VITE_BACKEND_API_BASE_URL', 'lib/app/router/app_router.dart', 'assets/l10n', 'BusinessOnboardingEnabled', 'WalletOutflowsEnabled']) {
    assert.ok(appSource.includes(fact), `laptop/customize fact ${fact}`);
  }
});
