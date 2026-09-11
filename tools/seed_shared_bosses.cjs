// One-time DB initialization. Existing documents are never overwritten.
// node tools/seed_shared_bosses.cjs /tmp/boss-seed.json load-alarm
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');
const source = process.argv[2], project = process.argv[3];
if (!source || !project) throw new Error('Usage: node tools/seed_shared_bosses.cjs seed.json project-id');
const seed = JSON.parse(fs.readFileSync(source, 'utf8'));
const globalModules = process.env.APPDATA ? path.join(process.env.APPDATA, 'npm/node_modules') : execFileSync('npm', ['root', '-g'], {encoding:'utf8'}).trim();
const auth = require(path.join(globalModules, 'firebase-tools/lib/auth.js'));
function field(v) {
  if(v===null)return {nullValue:null};
  if(typeof v==='string')return {stringValue:v};
  if(typeof v==='number')return {integerValue:String(v)};
  if(Array.isArray(v))return {arrayValue:{values:v.map(field)}};
  throw new Error('Unsupported seed value');
}
(async()=>{
 const account=auth.getGlobalDefaultAccount();
 const token=await auth.getAccessToken(account.tokens.refresh_token,account.tokens.scopes||[]);
 const headers={Authorization:'Bearer '+token.access_token,'Content-Type':'application/json'};
 const base=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
 let created=0, existing=0;
 for(const b of seed.bosses){
  if(!Number.isInteger(b.id) || b.id<=0 || !b.name)throw new Error('Invalid boss');
  const url=base+'/bossSchedules/'+b.id;
  const check=await fetch(url,{headers});
  if(check.ok){existing++;continue;}
  if(check.status!==404)throw new Error('DB check HTTP '+check.status);
  const data={...b};delete data.enabled;delete data.catalogVersion;
  const fields=Object.fromEntries(Object.entries(data).map(([k,v])=>[k,field(v)]));
  const name=`projects/${project}/databases/(default)/documents/bossSchedules/${b.id}`;
  const r=await fetch(base+':commit',{method:'POST',headers,body:JSON.stringify({writes:[{update:{name,fields},currentDocument:{exists:false},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]})});
  if(!r.ok)throw new Error('Seed HTTP '+r.status+': '+await r.text());
  created++;
 }
 console.log(`Shared DB initialized: ${created} created, ${existing} preserved in ${project}/bossSchedules`);
})().catch(e=>{console.error(e.message);process.exitCode=1;});
