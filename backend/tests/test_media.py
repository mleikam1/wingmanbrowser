"""Synthetic media only: no publisher photo fixtures or runtime network calls."""
import base64
import copy
import hashlib
import http.client
import io
import json
import tempfile
import threading
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path
from PIL import Image
from wingman_content.config import load_config, registry
from wingman_content.fetch import FetchResult, FetchError
from wingman_content.media import (accepts_image, accepts_image_url, cache_ttl, check_image, validate_image_policy,
    image_key, ingest_media, media_response, SecureImageFetcher)
from wingman_content.normalize import compatible_xml, parse_feed, iso
from wingman_content.server import BoundedServer, handler_for
from wingman_content.store import LocalStore
from test_content import SOURCE, Allow, rss

NOW = datetime.now(timezone.utc)
ROOT = Path(__file__).resolve().parents[2]


def source():
    s = copy.deepcopy(SOURCE)
    s['rights']['images'] = True
    s['displayMode'] = 'publisher-link'
    s['imagePolicy'] = {'kind': 'syndicated-feed-thumbnail', 'allowedHosts': ['media.example'],
        'pathPrefixes': ['/thumb/'], 'licenseUrl': 'https://public.example/terms', 'licenseLabel': 'Thumbnail terms',
        'credit': 'Test publisher', 'maximumWidth': 90, 'maximumHeight': 90}
    return s


def picture():
    return {'schemaVersion': 1, 'url': 'https://media.example/thumb/photo.png',
        'articleUrl': 'https://public.example/news/a', 'sourceId': SOURCE['id'],
        'credit': 'Test publisher', 'caption': 'Publisher thumbnail',
        'licenseUrl': 'https://public.example/terms', 'licenseLabel': 'Thumbnail terms',
        'basis': 'syndicated-feed-thumbnail', 'width': 90, 'height': 90}


def png(size=(90, 90)):
    out = io.BytesIO()
    Image.new('RGB', size, 'navy').save(out, 'PNG')
    return out.getvalue()


def snapshot(image=None):
    return {'sources': [], 'items': [{'id': 'a', 'sourceId': SOURCE['id'], 'image': image or picture(),
            'expiresAt': iso(NOW + timedelta(hours=1))}], 'revokedItemIds': [], 'revokedSourceIds': []}


class FakeImages:
    def __init__(self, headers=None):
        self.calls = []
        self.headers = headers or {'content-type': 'image/png', 'cache-control': 'public, max-age=600'}
    def fetch_image(self, image, source):
        self.calls.append(image['url'])
        return FetchResult(200, self.headers, png())


class MediaTests(unittest.TestCase):
    def test_decoder_rejects_mismatch_oversize_pixels_animation_and_svg(self):
        check_image(png(), picture(), 'image/png', source())
        for data, mime in [(png(), 'image/jpeg'), (png((91,90)), 'image/png'),
                           (b'<svg/>', 'image/svg+xml'), (b'x' * (1048576+1), 'image/png')]:
            with self.assertRaises(ValueError):
                check_image(data, picture(), mime, source())
        out = io.BytesIO()
        Image.new('RGB',(90,90),'red').save(out,'PNG',save_all=True,append_images=[Image.new('RGB',(90,90),'blue')])
        with self.assertRaises(ValueError):
            check_image(out.getvalue(), picture(), 'image/png', source())

    def test_thumbnail_scope_not_larger_or_tracking_assets(self):
        self.assertTrue(accepts_image(picture(), source()))
        for change in ({'width': 1200}, {'width': 1,'height':1}, {'url':'https://media.example/hero/a.png'},
                       {'url':'https://media.example/thumb/a.png?tracking=one'}, {'sourceId':'foreign'}, {'credit':'fake'}):
            self.assertFalse(accepts_image(dict(picture(), **change), source()))
        for uri in ['http://media.example/thumb/a', 'https://user@media.example/thumb/a',
                    'https://127.0.0.1/thumb/a', 'https://media.example/thumb/../a',
                    'https://media.example/thumb/%2e%2e/a']:
            self.assertFalse(accepts_image_url(uri, source()))

    def test_redirect_checked_against_exact_media_scope(self):
        fetcher = SecureImageFetcher()
        with self.assertRaises(FetchError):
            fetcher.checked_url('https://media.example/hero/a.png', source())

    def test_shared_cache_requires_explicit_permission_and_honors_age(self):
        self.assertEqual(cache_ttl({}),0)
        for directive in ['no-store','no-cache','private','max-age=0']:
            self.assertEqual(cache_ttl({'cache-control':directive}),0)
        self.assertEqual(cache_ttl({'cache-control':'public, max-age=600','age':'200'}),400)
        self.assertEqual(cache_ttl({'cache-control':'max-age=600, max-age=10'}),10)

    def test_image_key_matches_cross_platform_json_contract(self):
        p = picture()
        expected = hashlib.sha256(json.dumps(p,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        self.assertEqual(image_key(p),expected)
        ordered = {}
        for key,value in p.items():
            ordered[key]=value
            if key=='sourceId': ordered['articleId']='article'
        self.assertEqual(image_key(ordered),hashlib.sha256(json.dumps(ordered,separators=(',',':')).encode()).hexdigest())

    def test_media_ingestion_and_withdrawal_cache_gates(self):
        fetcher=FakeImages(); snap=snapshot(); config={'sources':[source()]}
        media, report=ingest_media(snap,config,{},NOW,fetcher)
        self.assertEqual(len(media),1)
        bundle={'snapshot':snap,'media':media}
        self.assertEqual(media_response(bundle,image_key(picture()),NOW)[0],png())
        self.assertIsNone(media_response(bundle,'https://evil.example',NOW))
        self.assertIsNone(media_response(bundle,image_key(picture()),NOW+timedelta(hours=1)))
        snap['revokedItemIds']=['a']
        self.assertIsNone(media_response(bundle,image_key(picture()),NOW))
        snap['revokedItemIds']=[]; snap['revokedSourceIds']=[SOURCE['id']]
        self.assertIsNone(media_response(bundle,image_key(picture()),NOW))
        snap['revokedSourceIds']=[]; snap['items']=[]
        self.assertIsNone(media_response(bundle,image_key(picture()),NOW))

    def test_no_store_never_enters_bundle(self):
        media,_=ingest_media(snapshot(),{'sources':[source()]},{},NOW,
            FakeImages({'content-type':'image/png','cache-control':'no-store'}))
        self.assertFalse(media)
        s=source(); s['displayMode']='sponsored-syndication'
        media,_=ingest_media(snapshot(),{'sources':[s]},{},NOW,FakeImages())
        self.assertFalse(media)

    def test_served_lifetime_cannot_outlive_media_story_or_publication_window(self):
        snap=snapshot()
        media,_=ingest_media(snap,{'sources':[source()]},{},NOW,FakeImages())
        bundle={'snapshot':snap,'media':media}; key=image_key(picture())
        self.assertGreater(media_response(bundle,key,NOW)[2],60)
        self.assertLessEqual(media_response(bundle,key,NOW)[2],600)
        snap['items'][0]['expiresAt']=iso(NOW+timedelta(seconds=20))
        self.assertLessEqual(media_response(bundle,key,NOW)[2],20)
        snap['items'][0]['expiresAt']=iso(NOW+timedelta(hours=1))
        snap['items'][0]['publishedAt']=iso(NOW-timedelta(days=30)+timedelta(seconds=10))
        self.assertLessEqual(media_response(bundle,key,NOW)[2],10)
        self.assertIsNone(media_response(bundle,key,NOW+timedelta(seconds=11)))

    def test_media_serving_has_no_fetch_or_arbitrary_url_route(self):
        with tempfile.TemporaryDirectory() as path:
            store=LocalStore(path); snap=snapshot()
            media,_=ingest_media(snap,{'sources':[source()]},{},NOW,FakeImages())
            store.write({'snapshot':snap,'media':media})
            server=BoundedServer(('127.0.0.1',0),handler_for(store))
            thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
            try:
                for path,expected in [('/v1/media/'+image_key(picture()),200),
                        ('/v1/media/'+image_key(picture())+'?url=https://evil.example',404),
                        ('/v1/media/https://evil.example',404),('/v1/media/'+'0'*64,404)]:
                    conn=http.client.HTTPConnection('127.0.0.1',server.server_port)
                    conn.request('GET',path); response=conn.getresponse(); data=response.read()
                    self.assertEqual(response.status,expected)
                    if expected==200:
                        self.assertEqual(response.getheader('Content-Type'),'image/png')
                        self.assertEqual(data,png())
                    conn.close()
            finally:
                server.shutdown(); server.server_close(); thread.join()

    def test_namespace_exact_thumbnail_not_channel_logo_or_hero(self):
        body=b'<rss xmlns:m="http://search.yahoo.com/mrss/"><channel><image><url>https://media.example/thumb/logo.png</url></image><item><title>Research</title><link>https://public.example/news/a</link><m:content url="https://media.example/hero/photo.png"/><m:thumbnail url="https://media.example/thumb/photo.png" width="90" height="90"/></item></channel></rss>'
        items,_,_=parse_feed(body,source(),NOW,Allow())
        self.assertEqual(items[0]['image']['url'],picture()['url'])
        items,_,_=parse_feed(body.replace(b'width="90"',b'width="1200"'),source(),NOW,Allow())
        self.assertIsNone(items[0]['image'])

    def test_only_exact_thumbnail_candidates_from_permitted_item_formats(self):
        fragments = [
            '<m:group><m:thumbnail url="https://media.example/thumb/photo.png" width="90" height="90"/></m:group>',
            '<m:content url="https://media.example/thumb/photo.png" type="image/png" width="90" height="90"/>',
            '<enclosure url="https://media.example/thumb/photo.png" type="image/png" width="90" height="90"/>',
            '<description><![CDATA[<img src="https://media.example/thumb/photo.png" width="90" height="90">]]></description>',
        ]
        for fragment in fragments:
            body=('<rss xmlns:m="http://search.yahoo.com/mrss/"><channel><item><title>Research</title><link>https://public.example/news/a</link>'+fragment+'</item></channel></rss>').encode()
            self.assertEqual(parse_feed(body,source(),NOW,Allow())[0][0]['image']['url'], picture()['url'])
            self.assertIsNone(parse_feed(body.replace(b'width="90"',b'width="900"'),source(),NOW,Allow())[0][0]['image'])

    def test_original_headline_excerpt_and_update_provenance(self):
        title='Long original science headline '+('word '*50).strip()
        body=rss('<item><title>'+title+'</title><link>https://public.example/news/a?utm_source=feed</link><description><![CDATA[<p>Publisher <b>summary</b>.</p><script>tracker</script>]]></description></item>')
        item=parse_feed(body,source(),NOW,Allow())[0][0]
        self.assertEqual(item['title'],title)
        self.assertNotIn('tracker',item['excerpt'])
        self.assertEqual(item['excerptProvenance']['field'],'rss-description')
        self.assertEqual(item['outboundUrl'],'https://public.example/news/a?utm_source=feed')
        self.assertEqual(item['canonicalUrl'],'https://public.example/news/a')

    def test_nasa_compatibility_is_exact_and_separate_from_strict_parser(self):
        config=load_config(ROOT/'backend/sources.json')
        s=next(s for s in config['sources'] if s['id']=='nasa-photojournal')
        bad=b'<rss xmlns:atom="http://www.w3.org/2005/Atom"><channel><atom:link href="https://science.nasa.gov/feed/?post_type=post&cat=19797&science_org=19791" rel="self" type="application/rss+xml"/><item></item></channel></rss>'
        self.assertNotEqual(compatible_xml(bad,s),bad)
        self.assertEqual(compatible_xml(bad,SOURCE),bad)
        parse_feed(bad,s,NOW,Allow())
        for data in [bad.replace(b'<item>',b'<item><title>bad & text</title>'),
                     b'<!DOCTYPE rss>'+bad, bad.replace(b'cat=19797',b'cat=other')]:
            with self.assertRaises(Exception): parse_feed(data,s,NOW,Allow())

    def test_registry_preserves_reviewed_image_and_syndication_contracts(self):
        c=load_config(ROOT/'backend/sources.json'); generated=registry(c)
        self.assertEqual(generated,json.loads((ROOT/'assets/live_content/sources.json').read_text()))
        # Ordinary title/link eligibility is now independent of photo delivery.
        self.assertFalse(generated['requireStoryImages'])
        byid={s['id']:s for s in generated['sources']}
        self.assertEqual(byid['newsusa-features']['displayMode'],'sponsored-syndication')
        self.assertFalse(byid['newsusa-features']['rights']['excerpts'])
        nasa=byid['nasa-photojournal']; image=next(iter(nasa['imagePolicy']['reviewedArticles'].values()))
        self.assertTrue(accepts_image(image,nasa))
        self.assertFalse(accepts_image(dict(image,articleId='fake'),nasa))
        self.assertFalse(accepts_image(dict(image,articleUrl='https://science.nasa.gov/photojournal/unreviewed/'),nasa))
        disabled = dict(nasa, enabled=False)
        validate_image_policy(disabled)
        self.assertFalse(accepts_image(image, disabled))


if __name__=='__main__': unittest.main()
