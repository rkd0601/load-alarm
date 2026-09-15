// Copy global bossSchedules from one Firebase project to another.
// Usage: node tools/copy_boss_schedules.cjs load-alarm load-alarm-dev
const path = require('path');
const {execFileSync} = require('child_process');
const sourceProject = process.argv[2];
const targetProject = process.argv[3];
if (!sourceProject || !targetProject) {
  throw new Error('Usage: node tools/copy_boss_schedules.cjs source-project target-project');
}
const globalModules = process.env.APPDATA
  ? path.join(process.env.APPDATA, 'npm/node_modules')
  : execFileSync('npm', ['root', '-g'], {encoding: 'utf8'}).trim();
const auth = require(path.join(globalModules, 'firebase-tools/lib/auth.js'));

function decodeValue(value) {
  if ('nullValue' in value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeValue);
  if ('mapValue' in value) {
    return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([k, v]) => [k, decodeValue(v)]));
  }
  throw new Error(`Unsupported Firestore value ${JSON.stringify(value)}`);
}
function encodeValue(value) {
  if (value === null || value === undefined) return {nullValue: null};
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'number') return {integerValue: String(value)};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encodeValue)}};
  if (typeof value === 'object') {
    return {mapValue: {fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encodeValue(v)]))}};
  }
  throw new Error(`Unsupported JS value ${JSON.stringify(value)}`);
}
function docToData(doc) {
  return Object.fromEntries(Object.entries(doc.fields || {}).map(([k, v]) => [k, decodeValue(v)]));
}
async function request(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${options?.method || 'GET'} ${url} HTTP ${response.status}: ${data.error?.message || text}`);
  return data;
}
(async () => {
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Firebase CLI login is required.');
  const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes || []);
  const headers = {Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json'};
  const sourceBase = `https://firestore.googleapis.com/v1/projects/${sourceProject}/databases/(default)/documents/bossSchedules`;
  const targetBase = `https://firestore.googleapis.com/v1/projects/${targetProject}/databases/(default)/documents`;
  const source = await request(`${sourceBase}?pageSize=100`, {headers});
  const docs = (source.documents || []).map((doc) => {
    const id = doc.name.split('/').pop();
    const data = docToData(doc);
    delete data.enabled;
    for (const key of Object.keys(data)) {
      if (key.endsWith('At') && typeof data[key] === 'string' && data[key].includes('T')) delete data[key];
    }
    return {id, data};
  }).sort((a, b) => Number(a.id) - Number(b.id));
  if (docs.length !== 45) throw new Error(`Expected 45 source bosses, got ${docs.length}`);
  const writes = docs.map(({id, data}) => ({
    update: {
      name: `projects/${targetProject}/databases/(default)/documents/bossSchedules/${id}`,
      fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, encodeValue(v)])),
    },
    updateTransforms: [{fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME'}],
  }));
  await request(`${targetBase}:commit`, {method: 'POST', headers, body: JSON.stringify({writes})});
  console.log(`Copied ${docs.length} bossSchedules from ${sourceProject} to ${targetProject}`);
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
