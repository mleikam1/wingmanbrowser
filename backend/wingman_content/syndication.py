"""The separately reviewed sponsored full-article adapter; no HTML rendering."""
import re
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, unquote

PROHIBITED = re.compile(r"\b(?:tobacco|nicotine|cigarettes?|cigars?|vaping|vapes?|e[- ]?cigarettes?|"
    r"alcohol(?:ic)?|liquor|spirits|beers?|wines?|winery|vodka|whisk(?:e)?y|bourbon|champagne|"
    r"cocktails?|brewer(?:y|ies)|cannabis|marijuana|hemp|cbd|thc|delta[- ]?(?:8|9)|"
    r"gambl\w*|casinos?|sportsbook\w*|bets?|betting|wagers?|lotter(?:y|ies)|porn\w*|adult entertainment|"
    r"adult dating|sex toys?|sexual wellness|drugs?|narcotics?|opioids?|fentanyl|cocaine|heroin|"
    r"methamphetamine|ketamine|psilocybin|retatrutide|prescription drugs?|prescription medications?)\b", re.I)
UNSAFE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]")


def acceptable(text):
    return len(text) <= 65536 and not UNSAFE.search(text) and not PROHIBITED.search(
        re.sub(r"\balcohol[- ]free\b", "", text, flags=re.I))


class ArticleReview(HTMLParser):
    def __init__(self, article, destination_policy):
        super().__init__(convert_charrefs=True)
        self.article, self.destination_policy = article, destination_policy
        self.text, self.nodes, self.depth = [], 0, 0

    def handle_starttag(self, tag, attrs):
        self.nodes += 1
        if tag not in {"div", "section", "article", "p", "h1", "h2", "h3", "h4", "h5", "h6",
                       "ul", "ol", "li", "a", "span", "strong", "b", "em", "i", "sup", "small", "img", "br"}:
            raise ValueError("unsupported-syndication-element")
        if tag not in {"img", "br"}:
            self.depth += 1
        if self.nodes > 4096 or self.depth > 24:
            raise ValueError("syndication-complexity")
        attrs = dict(attrs)
        if any(k.startswith("on") or k in {"hidden", "aria-hidden"} for k in attrs):
            raise ValueError("unsupported-syndication-attributes")
        if tag == "a" and "href" in attrs:
            url = urljoin(self.article, attrs["href"] or "")
            parsed = urlsplit(url)
            if (parsed.scheme not in {"http", "https"} or parsed.username or parsed.password or
                    not re.fullmatch(r"[a-z0-9-]+(?:\.[a-z0-9-]+)+", parsed.hostname or "") or
                    re.fullmatch(r"[0-9.]+", parsed.hostname or "") or
                    parsed.hostname.endswith((".local", ".localhost")) or
                    parsed.port not in (None, 443 if parsed.scheme == "https" else 80) or
                    re.search(r"[\x00-\x20\\]", url) or not acceptable(unquote(url)) or
                    not self.destination_policy.allows(url)):
                raise ValueError("unsafe-syndication-link")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in {"img", "br"}:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if tag not in {"img", "br"}:
            self.depth = max(0, self.depth - 1)

    def handle_data(self, data):
        self.text.append(data)


def article_payload(raw, url, source, destination_policy):
    if not raw or len(raw) > 65536 or UNSAFE.search(raw):
        raise ValueError("syndication-size-or-text")
    parser = ArticleReview(url, destination_policy)
    parser.feed(raw)
    parser.close()
    if not acceptable(" ".join(parser.text)) or not "".join(parser.text).strip():
        raise ValueError("restricted-syndication-content")
    # Exact supplied article, attribution and links. Client independently parses
    # into inert runs and applies stricter structural review before showing it.
    return {"schemaVersion": 1, "articleUrl": url, "publisher": source["name"],
            "licenseUrl": source["rights"]["licenseUrl"], "html": raw}


def feature_topics(title):
    rules = {
        "sports": r"\b(sports?|athletes?|football|baseball|basketball|golf|tennis|soccer)\b",
        "entertainment": r"\b(music|movies?|films?|books?|reading|entertainment|theater|arts?)\b",
        "technology": r"\b(technology|digital|online|cyber|computers?|phones?|AI)\b",
        "business": r"\b(business|financial|money|retirement|savings|banking|tax|career|jobs?)\b",
        "fashion": r"\b(fashion|style|beauty|skin|clothing|jewelry)\b",
        "food": r"\b(food|recipes?|cooking|kitchen|meals?|nutrition)\b",
        "health": r"\b(health|wellness|fitness|exercise|sleep|medical|care|patients?)\b",
        "travel": r"\b(travel|vacations?|trips?|tourism|destinations?)\b",
    }
    return [topic for topic, rule in rules.items() if re.search(rule, title, re.I)] or ["headlines"]
