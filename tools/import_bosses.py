import json,re,sys,zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.etree import ElementTree as E
ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
def main():
 with zipfile.ZipFile(sys.argv[1]) as z:
  strings=[''.join(t.itertext()) for t in E.fromstring(z.read('xl/sharedStrings.xml')).findall('s:si',ns)]
  def rows(n):
   result=[]
   for row in E.fromstring(z.read(f'xl/worksheets/sheet{n}.xml')).findall('.//s:row',ns):
    out={}
    for c in row.findall('s:c',ns):
     v=c.find('s:v',ns)
     if v is not None and v.text: out[re.sub(r'\d','',c.attrib['r'])]=(strings[int(v.text)] if c.get('t')=='s' else v.text).strip()
    result.append(out)
   return result
  details={}
  anchors={}
  for r in rows(2):
   for name,ability,loot,period in [('D','E','F','J'),('N','O','P','Q')]:
    if r.get(name) and r.get(period): details[r[name]]=(r.get(ability,''),r.get(loot,''),r[period])
  for r in rows(2):
   if r.get('D') and r.get('G'):
    try:
     serial=float(r['G'])
     if serial >= 1:
      instant=datetime(1899,12,30,tzinfo=timezone(timedelta(hours=9)))+timedelta(seconds=round(serial*86400))
      anchors[r['D']]=int(instant.timestamp()*1000)
    except ValueError: pass
  def fixed(v):
   m=re.search(r'(\d{1,2}):(\d{2})',v)
   assert m,v
   return [i+1 for i,d in enumerate('\uC6D4\uD654\uC218\uBAA9\uAE08\uD1A0\uC77C') if d in v[:m.start()].replace('\uC694\uC77C','')],int(m[1])*60+int(m[2])
  result=[]
  for r in rows(3):
   if r.get('E') not in ('\uD544\uB4DC','\uACE0\uC815'): continue
   ability,loot,period=details[r['C']]
   boss=dict(catalogVersion=20260911,id=len(result)+1,name=r['C'],region=r['A'],location=r.get('B',''),ability=ability,loot=loot,anchorMs=anchors.get(r['C']))
   if r['E']=='\uD544\uB4DC':
    minutes=round(float(r['D'])*1440)
    assert minutes==round(float(period)*1440),r['C']
    boss.update(intervalMinutes=minutes,weekdays=[],minuteOfDay=0)
   else:
    days,minute=fixed(r['D'])
    assert (days,minute)==fixed(period),r['C']
    boss.update(intervalMinutes=0,weekdays=days,minuteOfDay=minute)
   result.append(boss)
  assert len(result)==45
  metadata_keys=['id','name','region','location','ability','loot']
  Path('assets/bosses.json').write_text(json.dumps({'bosses':[{k:b[k] for k in metadata_keys} for b in result]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
  if len(sys.argv)<3: raise SystemExit('DB 가져오기 출력 경로를 지정하세요: python3 tools/import_bosses.py source.xlsx /tmp/boss-seed.json')
  Path(sys.argv[2]).write_text(json.dumps({'schemaVersion':1,'bosses':result},ensure_ascii=False,indent=2),encoding='utf-8')
  print(f'Validated {len(result)} bosses; {len(anchors)} dated kill times. DB import file: {sys.argv[2]}')
if __name__=='__main__': main()
