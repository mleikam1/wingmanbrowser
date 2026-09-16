"""No network: build clearly labeled snapshots for the real app verification."""
from datetime import datetime, timezone
from wingman_content.config import load_config
from wingman_content.currents import CATEGORIES
from wingman_content.normalize import DestinationPolicy, parse_currents_news, iso
from wingman_content.provider import public_snapshot
from wingman_content.store import LocalStore
now=datetime.now(timezone.utc)
config=load_config('backend/sources.json')
source=next(s for s in config['sources'] if s['id']=='currents')
policy=DestinationPolicy('assets/policy/consumer_protection.json')
items=[]
for category in CATEGORIES:
    rows=[{'id':f'fixture-{category}-{i}', 'title':f'Fixture {category.replace("_", " ")} story {i}',
           'description':'Controlled integration fixture for original publisher previews and protected navigation.' + (' Scientists study physics and software technology.' if category=='science_technology' else ' Recipes, clothing and travel tourism.' if category=='lifestyle_leisure' else ''),
           'url':f'https://example.com/wingman-fixture/{category}/{i}',
           'published':iso(now), 'category':[category], 'language':'en',
           'source':{'name':'Example Publisher', 'domain':'example.com'}, 'image':None}
          for i in range(12)]
    normalized,held=parse_currents_news(rows,source,now,policy,provider_category=category)
    assert len(normalized)==12, held
    items.extend(normalized)
state={'items':items,'lastSuccessAt':iso(now),'fetchedAt':iso(now),'status':'fresh',
       'nextRefreshAt':iso(now.replace(year=now.year+1))}
snapshot=public_snapshot(config,{'currents':state},now)
LocalStore('work/currents-app-fixture').write({'schemaVersion':1,'states':{'currents':state},'snapshot':snapshot,'media':{}})
print('Fixture-only real-app snapshot:',len(snapshot['items']),'items; upstream calls: 0')
