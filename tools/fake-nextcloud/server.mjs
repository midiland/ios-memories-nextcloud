// Fake Nextcloud + Memories server for testing the iOS app's code-loading checks on a simulator.
//
// Serves just enough for the app: `api/describe` (with the asset manifest) and the web files of
// a tiny fake Memories frontend. The manifest is signed with the development key of
// `webpack.manifest-sign-plugin.ts`, which Debug builds accept (Release builds must reject it).
//
//   node tools/fake-nextcloud/server.mjs            # listens on http://localhost:18090
//   curl -s localhost:18090/__scenario/unsigned     # switch scenario at runtime
//
// Scenarios (what `describe?manifest=1` returns):
//   valid      signed manifest, files match                → the fake page loads
//   unsigned   manifest without signature                  → "could not be verified" error
//   tampered   signed manifest, memories-main.js modified  → "does not match its signature" error
//   newformat  DSSE envelope (format of Memories master)   → "could not be verified" error
//   none       no manifest at all                          → "could not be verified" error
import { createHash, createPrivateKey, sign } from 'node:crypto';
import { createServer } from 'node:http';

const PORT = Number(process.env.PORT ?? 18090);
const ORIGIN = `http://localhost:${PORT}`;
const SCENARIOS = ['valid', 'unsigned', 'tampered', 'newformat', 'none'];
let scenario = process.env.SCENARIO ?? 'valid';

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
    case 'newformat':
      return { ...body, cssManifest: [], jsManifest: { payloadType: 'application/vnd.tuf+json', payload: 'e30=', signatures: [{ sig: 'AA==' }] } };
    default:
      return { ...body, ...manifestFields(scenario) };
  }
}

const send = (res, status, type, body) => {
  res.writeHead(status, { 'Content-Type': type, 'Content-Length': Buffer.byteLength(body) });
  res.end(body);
};

createServer((req, res) => {
  const url = new URL(req.url, ORIGIN);
  const path = url.pathname;
  console.log(`[${scenario}] ${req.method} ${req.url}`);

  if (path.startsWith('/__scenario/')) {
    const next = path.slice('/__scenario/'.length);
    if (!SCENARIOS.includes(next)) return send(res, 400, 'text/plain', `unknown scenario, use: ${SCENARIOS.join(', ')}\n`);
    scenario = next;
    return send(res, 200, 'text/plain', `scenario: ${scenario}\n`);
  }
  if (path === '/index.php/apps/memories/api/describe') {
    return send(res, 200, 'application/json', JSON.stringify(describe(url, Boolean(req.headers.authorization))));
  }
  const file = path.match(/^\/apps\/memories\/js\/([\w.-]+)$/)?.[1];
  if (file && files[file]) {
    const name = url.searchParams.get('v') ?? scenario;
    const body = scenario === 'tampered' && file === 'memories-main.js' ? `${files[file](name)}// modified\n` : files[file](name);
    return send(res, 200, 'text/javascript', body);
  }
  // Anything the fake frontend could relay (config, days…): empty JSON.
  send(res, 200, 'application/json', '{}');
}).listen(PORT, () => console.log(`Fake Nextcloud on ${ORIGIN} (scenario: ${scenario})`));
