// Uses temporary anonymous users and removes only their verification data.
// Run: node tools/firebase_smoke.cjs config/firebase.android.json
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const {execFileSync} = require('child_process');
// Resolve and validate cleanup access before creating any test users.
const globalModules = process.env.APPDATA
  ? path.join(process.env.APPDATA, 'npm/node_modules')
  : execFileSync('npm', ['root', '-g'], {encoding: 'utf8'}).trim();
const firebaseAuth = require(path.join(globalModules, 'firebase-tools/lib/auth.js'));
let cleanupToken;
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
  const account = firebaseAuth.getGlobalDefaultAccount();
  if (!account) throw new Error('Firebase CLI login is required for test cleanup.');
  cleanupToken = (await firebaseAuth.getAccessToken(
    account.tokens.refresh_token, account.tokens.scopes || [])).access_token;
  for (let i = 0; i < 2; i++) {
    users.push(requireSuccess(await request(`${authBase}signUp?key=${config.FIREBASE_API_KEY}`,
      'POST', {returnSecureToken:true}), 'Anonymous sign-in'));
  }
  const url = `${base}/bossSchedules/1`;
  const first = requireSuccess(await request(url,'GET',null,users[0].idToken), 'Shared read A');
  const second = requireSuccess(await request(url,'GET',null,users[1].idToken), 'Shared read B');
  assert.deepEqual(first.fields, second.fields);
  console.log('PASS: two anonymous users read the same shared boss');
  const all = requireSuccess(await request(`${base}/bossSchedules?pageSize=100`,'GET',null,users[0].idToken), 'Shared list');
  assert.equal(all.documents.length,45);
  console.log('PASS: shared DB contains 45 bosses');
  // Validate a real authorized write without changing any boss time. The
  // precondition prevents overwriting a concurrent user's edit.
  const write = {update:{name:first.name,fields:{intervalMinutes:first.fields.intervalMinutes}},
    updateMask:{fieldPaths:['intervalMinutes']},currentDocument:{updateTime:first.updateTime},
    updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
  requireSuccess(await request(`${base}:commit`,'POST',{writes:[write]},users[0].idToken), 'Shared same-value write');
  const changed = requireSuccess(await request(url,'GET',null,users[1].idToken), 'Other user sees write');
  assert.notEqual(changed.updateTime, first.updateTime);
  assert.deepEqual(changed.fields.intervalMinutes, first.fields.intervalMinutes);
  console.log('PASS: shared update visible to another user; time value unchanged');
  const unauthorized = await request(url);
  assert.equal(unauthorized.status,403);
  for (const [fieldName,value] of [['enabled',{booleanValue:true}],['intervalMinutes',{integerValue:'0'}],['name',{stringValue:'invalid'}]]) {
    const bad = {update:{name:first.name,fields:{[fieldName]:value}},updateMask:{fieldPaths:[fieldName]},
      updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
    assert.equal((await request(`${base}:commit`,'POST',{writes:[bad]},users[0].idToken)).status,403);
  }
  console.log('PASS: unauthenticated access, invalid time, shared alarm preference and name edits denied');
}
async function cleanup() {
  if (documentName) {
    requireSuccess(await request('https://firestore.googleapis.com/v1/'+documentName, 'DELETE', null, cleanupToken), 'Test document cleanup');
  }
  for (const user of users) {
    requireSuccess(await request(`${authBase}delete?key=${config.FIREBASE_API_KEY}`, 'POST', {idToken: user.idToken}), 'Test account cleanup');
  }
  if (users.length) console.log('PASS: temporary accounts and data removed');
}
main().catch(e => {console.error(e.message);process.exitCode=1;})
  .finally(() => cleanup().catch(e => {console.error(e.message);process.exitCode=1;}));
