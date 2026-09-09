import json,re,sys,zipfile
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
  for r in rows(2):
   for name,ability,loot,period in [('D','E','F','J'),('N','O','P','Q')]:
    if r.get(name) and r.get(period): details[r[name]]=(r.get(ability,''),r.get(loot,''),r[period])
  def fixed(v):
   m=re.search(r'(\d{1,2}):(\d{2})',v)
   assert m,v
   return [i+1 for i,d in enumerate('\uC6D4\uD654\uC218\uBAA9\uAE08\uD1A0\uC77C') if d in v[:m.start()].replace('\uC694\uC77C','')],int(m[1])*60+int(m[2])
  result=[]
  for r in rows(3):
   if r.get('E') not in ('\uD544\uB4DC','\uACE0\uC815'): continue
   ability,loot,period=details[r['C']]
   boss=dict(id=len(result)+1,name=r['C'],region=r['A'],location=r.get('B',''),ability=ability,loot=loot,enabled=False,anchorMs=None)
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
  Path('assets/bosses.json').write_text(json.dumps(dict(schemaVersion=1,timezone='Asia/Seoul',source='https://docs.google.com/spreadsheets/d/1b8pYSKejoEAAlao9H0KyKWhfpHKaFdg-XEiCXEXf7Jo',sheets=[2,3],bosses=result),ensure_ascii=False,indent=2),encoding='utf-8')
  print(f'Imported {len(result)} bosses; all schedules agree across sheets 2 and 3.')
if __name__=='__main__': main()
