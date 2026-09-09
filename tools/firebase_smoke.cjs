// Uses temporary anonymous users and removes only their verification data.
// Run: node tools/firebase_smoke.cjs config/firebase.android.json
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const config = JSON.parse(fs.readFileSync(process.argv[2] || 'config/firebase.android.json', 'utf8'));
const project = config.FIREBASE_PROJECT_ID;
const base = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const authBase = 'https://identitytoolkit.googleapis.com/v1/accounts:';
const users = [];
let documentName;

async function request(url, method = 'GET', body, token) {
  const headers = {'Content-Type': 'application/json'};
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, {method, headers, body: body ? JSON.stringify(body) : undefined});
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  return {status: response.status, data};
}
function requireSuccess(result, label) {
  if (result.status < 200 || result.status >= 300) {
    throw new Error(`${label}: HTTP ${result.status} ${result.data.error?.message || ''}`);
  }
  return result.data;
}
function field(value) {
  if (value === null) return {nullValue: null};
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'number') return {integerValue: String(value)};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(field)}};
  return {mapValue: {fields: Object.fromEntries(Object.entries(value).map(([k,v]) => [k,field(v)]))}};
}
async function main() {
  for (let i = 0; i < 2; i++) {
    const user = requireSuccess(await request(`${authBase}signUp?key=${config.FIREBASE_API_KEY}`, 'POST', {returnSecureToken: true}), 'Anonymous sign-in');
    users.push(user);
  }
  console.log('PASS: anonymous sign-in');
  const uid = users[0].localId;
  documentName = `projects/${project}/databases/(default)/documents/bossAlarmUsers/${uid}/schedules/current`;
  const url = `${base}/bossAlarmUsers/${uid}/schedules/current`;
  const document = JSON.parse(fs.readFileSync('assets/bosses.json', 'utf8'));
  const fields = field({schemaVersion: 1, bosses: document.bosses}).mapValue.fields;
  const write = {update: {name: documentName, fields}, updateTransforms: [{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
  requireSuccess(await request(`${base}:commit`, 'POST', {writes:[write]}, users[0].idToken), 'Own schedule write');
  const stored = requireSuccess(await request(url, 'GET', null, users[0].idToken), 'Own schedule read');
  assert.equal(stored.fields.bosses.arrayValue.values.length, 45);
  console.log('PASS: 45-boss schedule write/read');
  const denied = [
    ['unauthenticated read', await request(url)],
    ['other user read', await request(url, 'GET', null, users[1].idToken)],
    ['other user write', await request(`${base}:commit`, 'POST', {writes:[write]}, users[1].idToken)],
    ['malformed write', await request(`${base}:commit`, 'POST', {writes:[{...write,update:{name:documentName,fields:{...fields,schemaVersion:{integerValue:'2'}}}}]}, users[0].idToken)]
  ];
  for (const [label, result] of denied) {
    assert.equal(result.status, 403, `${label} must be rejected`);
    console.log(`PASS: ${label} denied`);
  }
}
async function cleanup() {
  if (documentName) {
    const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
    const account = auth.getGlobalDefaultAccount();
    const token = await auth.getAccessToken(account.tokens.refresh_token, account.tokens.scopes || []);
    requireSuccess(await request('https://firestore.googleapis.com/v1/'+documentName, 'DELETE', null, token.access_token), 'Test document cleanup');
  }
  for (const user of users) {
    requireSuccess(await request(`${authBase}delete?key=${config.FIREBASE_API_KEY}`, 'POST', {idToken: user.idToken}), 'Test account cleanup');
  }
  if (users.length) console.log('PASS: temporary accounts and data removed');
}
main().catch(e => {console.error(e.message);process.exitCode=1;})
  .finally(() => cleanup().catch(e => {console.error(e.message);process.exitCode=1;}));
