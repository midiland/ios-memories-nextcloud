// Fake Nextcloud + Memories server for testing the iOS app's code-loading checks on a simulator.
//
// Serves just enough for the app: `api/describe` (with the asset manifest) and the web files of
// a tiny fake Memories frontend. Manifests are signed with the development key of
// `webpack.manifest-sign-plugin.ts`, which Debug builds accept (Release builds must reject it),
// in the Memories 9 format (base64 manifest + jsManifestSig) or the Memories 10 one (DSSE + TUF).
//
//   node tools/fake-nextcloud/server.mjs            # listens on http://localhost:18090
//   curl -s localhost:18090/__scenario/unsigned     # switch scenario at runtime
//
// Scenarios (what `describe?manifest=1` returns):
//   valid          Memories 9 signed manifest, files match      → the fake page loads
//   unsigned       Memories 9 manifest without signature        → "could not be verified" error
//   tampered       Memories 9, memories-main.js modified        → "does not match its signature" error
//   dsse           Memories 10 DSSE envelope, files match       → the fake page loads
//   dsse-expired   DSSE envelope, TUF targets expired           → "could not be verified" error
//   dsse-tampered  DSSE envelope, memories-main.js modified     → "does not match its signature" error
//   dsse-old       DSSE envelope, lower TUF version than `dsse` → page loads on a fresh install;
//                  after `dsse`, refused as a rollback (banner), like `valid` after `dsse`
//   none           no manifest at all                           → "could not be verified" error
//   wipe           like `valid`, but `core/wipe/check` returns a pending wipe (issue #15)
import { createHash, createPrivateKey, sign } from 'node:crypto';
import { createServer } from 'node:http';

const PORT = Number(process.env.PORT ?? 18090);
const ORIGIN = `http://localhost:${PORT}`;
const SCENARIOS = ['valid', 'unsigned', 'tampered', 'dsse', 'dsse-expired', 'dsse-tampered', 'dsse-old', 'none', 'wipe'];
let scenario = process.env.SCENARIO ?? 'valid';

/** Tokens that have a pending remote wipe (scenario `wipe` marks the test app password). */
const WIPE_TOKENS = new Set();
/** The app password the fake login flow hands out (any token works for the fake server). */
const TEST_APP_PASSWORD = 'test-app-password';

// Development signing key: the public default seed of webpack.manifest-sign-plugin.ts.
const DEV_SEED = Buffer.from('BfC97bs84avvLGpUfd0SkOuugTifNffExQ1IS88z58s=', 'base64');
const PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');
const devKey = createPrivateKey({ key: Buffer.concat([PKCS8_PREFIX, DEV_SEED]), format: 'der', type: 'pkcs8' });

const mainJS = (name) => `
document.getElementById('content').innerHTML =
  '<div style="font:20px -apple-system;padding:40px;text-align:center">' +
  '<h1>Fake Memories</h1><p>Scenario: <b>${name}</b></p>' +
  '<p>Loaded from the verified snapshot</p></div>';
`;
const files = { 'memories-main.js': mainJS, 'memories-l10n.js': () => '// fake l10n\n' };
const sha256 = (text) => createHash('sha256').update(text).digest('hex');

/** Old-format manifest fields: base64 JSON `{file: {hash, href}}` + base64 `{curve25519: sig}`. */
function manifestFields(name) {
  const manifest = {};
  for (const [file, body] of Object.entries(files)) {
    // The snapshot is keyed by the manifest: the version query changes it with the scenario.
    manifest[file] = { hash: sha256(body(name)), href: `/apps/memories/js/${file}?v=${name}` };
  }
  const bytes = Buffer.from(JSON.stringify(manifest));
  const fields = { jsManifest: bytes.toString('base64'), cssManifest: [] };
  if (name !== 'unsigned') {
    const sig = sign(null, bytes, devKey).toString('base64');
    fields.jsManifestSig = Buffer.from(JSON.stringify({ curve25519: sig })).toString('base64');
  }
  return fields;
}

/** Memories 10 manifest: DSSE envelope over TUF targets, signed over the DSSE pre-auth encoding. */
function dsseFields(name) {
  const targets = {};
  for (const [file, body] of Object.entries(files)) {
    const bytes = Buffer.from(body(name));
    targets[file] = {
      length: bytes.length,
      hashes: { sha256: sha256(bytes) },
      custom: { href: `/apps/memories/js/${file}?v=${name}` },
    };
  }
  const expires = name === 'dsse-expired' ? '2020-01-01T00:00:00Z' : '2099-01-01T00:00:00Z';
  const version = name === 'dsse-old' ? 1000 : 2000;
  const payload = Buffer.from(JSON.stringify({ _type: 'targets', spec_version: '1.0.0', version, expires, targets }));
  const type = 'application/vnd.tuf+json';
  const pae = Buffer.concat([
    Buffer.from(`DSSEv1 ${Buffer.byteLength(type)} ${type} ${payload.length} `),
    payload,
  ]);
  const sig = sign(null, pae, devKey).toString('base64');
  return {
    cssManifest: [],
    jsManifest: { payload: payload.toString('base64'), payloadType: type, signatures: [{ keyid: 'dev', sig }] },
  };
}

function describe(url, authorized) {
  const body = {
    version: '9.0.1',
    baseUrl: `${ORIGIN}/index.php/apps/memories/`,
    loginFlowUrl: `${ORIGIN}/index.php/login/v2`,
    uid: authorized ? 'tester' : null,
  };
  if (url.searchParams.get('manifest') !== '1') return body;
  switch (scenario) {
    case 'none':
      return body;
    case 'dsse':
    case 'dsse-expired':
    case 'dsse-tampered':
    case 'dsse-old':
      return { ...body, version: '10.0.0', ...dsseFields(scenario) };
    default:
      return { ...body, ...manifestFields(scenario) };
  }
}

const send = (res, status, type, body) => {
  res.writeHead(status, { 'Content-Type': type, 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
};

/** Reads a form-encoded POST body (`token=…`) into a plain object. */
function readFormBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => resolve(Object.fromEntries(new URLSearchParams(body))));
  });
}

createServer(async (req, res) => {
  const url = new URL(req.url, ORIGIN);
  const path = url.pathname;
  console.log(`[${scenario}] ${req.method} ${req.url}`);

  if (path.startsWith('/__scenario/')) {
    const next = path.slice('/__scenario/'.length);
    if (!SCENARIOS.includes(next)) return send(res, 400, 'text/plain', `unknown scenario, use: ${SCENARIOS.join(', ')}\n`);
    scenario = next;
    if (scenario === 'wipe') WIPE_TOKENS.add(TEST_APP_PASSWORD);
    return send(res, 200, 'text/plain', `scenario: ${scenario}\n`);
  }
  if (path === '/index.php/apps/memories/api/describe') {
    return send(res, 200, 'application/json', JSON.stringify(describe(url, Boolean(req.headers.authorization))));
  }

  // Remote wipe endpoints (issue #15): #[PublicPage], the token is the credential.
  if (path === '/index.php/core/wipe/check' && req.method === 'POST') {
    const { token } = await readFormBody(req);
    if (scenario === 'wipe' && WIPE_TOKENS.has(token)) {
      return send(res, 200, 'application/json', JSON.stringify({ wipe: true }));
    }
    return send(res, 404, 'application/json', '[]');
  }
  if (path === '/index.php/core/wipe/success' && req.method === 'POST') {
    const { token } = await readFormBody(req);
    WIPE_TOKENS.delete(token);
    console.log(`[${scenario}] wipe confirmed for token`);
    return send(res, 200, 'application/json', '[]');
  }

  const file = path.match(/^\/apps\/memories\/js\/([\w.-]+)$/)?.[1];
  if (file && files[file]) {
    const name = url.searchParams.get('v') ?? scenario;
    const body = ['tampered', 'dsse-tampered'].includes(scenario) && file === 'memories-main.js' ? `${files[file](name)}// modified\n` : files[file](name);
    return send(res, 200, 'text/javascript', body);
  }
  // Anything the fake frontend could relay (config, days…): empty JSON.
  send(res, 200, 'application/json', '{}');
}).listen(PORT, () => console.log(`Fake Nextcloud on ${ORIGIN} (scenario: ${scenario})`));
