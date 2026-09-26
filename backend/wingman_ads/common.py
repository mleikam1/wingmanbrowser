import base64
from datetime import datetime, timezone
import hashlib
import hmac
import json
import re
import time
from pathlib import Path
from urllib.parse import urlsplit

TTL = 900
INTENTS = frozenset({'productivity', 'learning', 'office', 'outdoors', 'security-tools'})
SECTIONS = frozenset({'untargeted', 'science', 'technology', 'arts', 'outdoors'})
TARGETS = INTENTS | SECTIONS
PLACEMENTS = frozenset({'search', 'newtab', 'news'})

class AdsError(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)

def now_seconds():
    return int(time.time())

def integer(value, minimum=0, maximum=10**12):
    if type(value) is not int or not minimum <= value <= maximum:
        raise AdsError('invalid-number')
    return value

def text(value, maximum=300, *, empty=False):
    if (not isinstance(value, str) or (not value.strip() and not empty) or len(value) > maximum
            or any(ord(c) < 32 or ord(c) == 127 for c in value) or '<' in value or '>' in value):
        raise AdsError('invalid-text')
    return value.strip()

def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,79}', value):
        raise AdsError('invalid-reference')
    return value

def iso(timestamp):
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')

def day(timestamp):
    return iso(timestamp)[:10]

def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True)

def live_approval(path, store_path, clock=now_seconds):
    """Owner-managed evidence, not permission inferred from a cloud default."""
    from wingman_search.secrets import validate_local_path
    try:
        path = validate_local_path(Path(path), require_file=True)
        if path.stat().st_size > 16384:
            raise ValueError()
        from wingman_search.contracts import decode_json
        value = decode_json(path.read_bytes(),16384)
        required = {'schemaVersion','environment','storePath','operatorHostId','productionOrigin','expiresAt',
                    'deploymentReference','liveAdsReference','financeReference','manualPaymentsReference',
                    'deploymentApproved','liveAdsApproved','financeApproved','manualPaymentsApproved',
                    'durableStorage','singleHost','partnerDemandEnabled','secondSearchAdEnabled'}
        if (not isinstance(value,dict) or set(value)!=required or value['schemaVersion']!=1
                or value['environment']!='single-durable-host' or value['storePath']!=str(Path(store_path).absolute())
                or type(value['expiresAt']) is not int or not clock()<value['expiresAt']<=clock()+366*86400
                or any(value[name] is not True for name in ('deploymentApproved','liveAdsApproved','financeApproved',
                       'manualPaymentsApproved','durableStorage','singleHost'))
                or value['partnerDemandEnabled'] is not False or type(value['secondSearchAdEnabled']) is not bool):
            raise ValueError()
        for name in ('operatorHostId','deploymentReference','liveAdsReference','financeReference','manualPaymentsReference'):
            identifier(value[name])
        origin = urlsplit(value['productionOrigin'])
        from wingman_search.config import validate_production_url
        validate_production_url(value['productionOrigin'])
        if origin.path or origin.query or origin.fragment:
            raise ValueError()
        return value
    except Exception:
        raise AdsError('live-finance-authorization-required') from None

def experiment_approval(path, clock=now_seconds):
    """Separate owner evidence for dormant density/exploration experiments."""
    from wingman_search.secrets import validate_local_path
    from wingman_search.contracts import decode_json
    try:
        path=validate_local_path(Path(path),require_file=True)
        if path.stat().st_size>4096: raise ValueError()
        value=decode_json(path.read_bytes(),4096)
        fields={'ownerApproved','expiresAt','demandReference','stableLayoutReference','relevanceReference',
                'incrementalNetContributionReference','qualityLatencyReference','secondSearchAdEnabled','explorationEnabled'}
        if (not isinstance(value,dict) or set(value)!=fields or value['ownerApproved'] is not True
                or type(value['expiresAt']) is not int or not clock()<value['expiresAt']<=clock()+30*86400
                or any(type(value[k]) is not bool for k in ('secondSearchAdEnabled','explorationEnabled'))): raise ValueError()
        for k in fields-{'ownerApproved','expiresAt','secondSearchAdEnabled','explorationEnabled'}: identifier(value[k])
        return value
    except Exception:
        raise AdsError('experiment-authorization-required') from None

class Tokens:
    def __init__(self, key, clock=now_seconds):
        if not isinstance(key, bytes) or len(key) != 32:
            raise AdsError('signing-key-required')
        self.key, self.clock = key, clock

    def sign(self, purpose, payload):
        body = base64.urlsafe_b64encode(encode(dict(payload, purpose=purpose)).encode()).rstrip(b'=')
        signature = hmac.digest(self.key, body, hashlib.sha256)
        return (body + b'.' + base64.urlsafe_b64encode(signature).rstrip(b'=')).decode()

    def read(self, token, purpose):
        try:
            if not isinstance(token, str) or len(token) > 4096 or not re.fullmatch(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', token):
                raise ValueError()
            body, signature = token.encode().split(b'.')
            received = base64.urlsafe_b64decode(signature + b'=' * (-len(signature) % 4))
            if not hmac.compare_digest(received, hmac.digest(self.key, body, hashlib.sha256)):
                raise ValueError()
            result = json.loads(base64.urlsafe_b64decode(body + b'=' * (-len(body) % 4)))
            now = self.clock()
            if (result.get('purpose') != purpose or type(result.get('iat')) is not int
                    or type(result.get('exp')) is not int or not result['iat'] <= now < result['exp']
                    or result['exp'] - result['iat'] != TTL):
                raise ValueError()
            return result
        except (ValueError, TypeError, KeyError, UnicodeError):
            raise AdsError('invalid-or-expired-token') from None
