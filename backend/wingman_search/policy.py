"""Additional conservative query/result/advertisement checks, without a bypass.

This is a bounded lexical layer alongside the pinned destination baseline and
Brave strict search, not a whole-web semantic or image-safety certification.
Nothing here retains queries or learns user interests.
"""
import re
import unicodedata
from urllib.parse import unquote, urlsplit
from pathlib import Path
from wingman_content.normalize import DestinationPolicy, public_article_host

REPO = Path(__file__).resolve().parents[2]
_PROMOTION = re.compile(r'\b(?:buy|shop|order|sale|discount|bonus|promo|free spins|place bets|bet now|watch|download)\b')
_RESTRICTED = re.compile(r'\b(?:porn(?:ography|ographic)?|xxx|nudes?|sex videos?|casino|sportsbook|gambl(?:e|ing)|betting|vapes?|vaping|cigarettes?|tobacco|nicotine|cannabis|marijuana|cocaine|heroin|vodka|whisk(?:e)?y|beer|wine|alcohol)\b')
_EDUCATION = re.compile(r'\b(?:addiction help|recovery|quit(?:ting)?|cessation|health effects|medical|education|research|study|report|news|history|treatment|prevention)\b')
_SENSITIVE = re.compile(r'\b(?:health|medical|doctor|cancer|pregnan\w*|symptoms?|diagnosis|therapy|depression|suicide|addiction|recovery|religion|politic\w*|election|sexual\w*|debt|bankrupt\w*|loan|credit|mortgage|divorce|abuse|unemploy\w*|disability|race|ethnic\w*|gender|password reset|log ?in|account|payment|student|school)\b')
_INTENTS = {
    'productivity': (r'\b(?:buy |compare |best )?(?:productivity tools?|task managers?|note taking apps?)\b',),
    'learning': (r'\b(?:buy |compare |best )?(?:learning software|language courses|coding courses)\b',),
    'office': (r'\b(?:buy |compare |best )?(?:office chairs?|standing desks?|notebooks?|desk lamps?)\b',),
    'outdoors': (r'\b(?:buy |compare |best )?(?:hiking boots?|camping tents?|backpacks?)\b',),
    'security-tools': (r'\b(?:buy |compare |best )?password managers?\b',),
}

def normalized(text):
    value = unicodedata.normalize('NFKC', text).casefold()
    for _ in range(2):
        value = unquote(value)
    value = re.sub(r'[\u200b-\u200f\u202a-\u202e\u2060-\u206f]', '', value)
    value = value.translate(str.maketrans({'0': 'o', '4': 'a', '@': 'a', '$': 's'}))
    value = re.sub(r'p[ ._-]*o[ ._-]*r[ ._-]*n', 'porn', value)
    return ' '.join(value.split())

def query_allowed(text):
    value = normalized(text)
    if re.search(r'\b(?:safesearch|safe search)\s*(?:=|:)\s*(?:off|false|o|moderate)\b', value):
        return False
    if _RESTRICTED.search(value):
        return bool(_EDUCATION.search(value)) and not bool(_PROMOTION.search(value))
    return not bool(re.search(r'\b(?:sexual exploitation|child sexual abuse images|steal passwords|ransomware for sale)\b', value))

def ad_context(text, *, altered=None):
    value = normalized(text)
    if (not query_allowed(text) or _RESTRICTED.search(value) or _SENSITIVE.search(value)
            or '@' in text or re.search(r'\b\d{5,}\b', text)):
        return None
    # A provider rewrite is never silently monetized as the original intent.
    if altered is not None and normalized(altered) != value:
        return None
    matches = [key for key, patterns in _INTENTS.items() if any(re.fullmatch(p, value) for p in patterns)]
    return matches[0] if len(matches) == 1 else None

class SearchPolicy:
    def __init__(self, baseline=None):
        self.destinations = DestinationPolicy(baseline or REPO / 'assets/policy/consumer_protection.json')

    def allows_url(self, value):
        if (not isinstance(value, str) or len(value) > 4096 or '\\' in value
                or any(ord(c) < 33 or ord(c) == 127 for c in value)):
            return False
        try:
            uri = urlsplit(value)
            decoded = unquote(unquote(uri.path))
            return (uri.scheme == 'https' and public_article_host(uri.hostname)
                    and uri.hostname not in ('api.search.brave.com',)
                    and uri.username is None and uri.password is None
                    and uri.port in (None, 443)
                    and '//' not in decoded
                    and not re.search(r'%(?:2f|5c|2e|25|00|0d|0a)', decoded, re.I)
                    and not any(p in ('.', '..') for p in decoded.split('/'))
                    and not any(c in decoded for c in ('\\', '\x00', '\r', '\n'))
                    and self.destinations.allows(uri._replace(path=decoded).geturl()))
        except (ValueError, UnicodeError):
            return False

    def allows_result(self, title, description, url):
        return bool(title) and self.allows_url(url) and query_allowed(title + ' ' + description)
