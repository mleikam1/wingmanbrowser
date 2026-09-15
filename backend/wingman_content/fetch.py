"""Bounded HTTPS fetching for configured feeds only; never an arbitrary URL proxy."""
import http.client
import ipaddress
import multiprocessing
import socket
import ssl
import threading
import time
import zlib
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit, urlunsplit

MAX_WIRE_BYTES = 1024 * 1024
MAX_XML_BYTES = 2 * 1024 * 1024
MAX_HEADERS_BYTES = 32768
MAX_REDIRECTS = 3
FETCH_DEADLINE_SECONDS = 25
SOCKET_TIMEOUT_SECONDS = 8
XML_TYPES = {"application/rss+xml", "application/atom+xml", "application/xml", "text/xml"}


class FetchError(Exception):
    def __init__(self, reason, retry_after=None):
        super().__init__(reason)
        self.reason = reason
        self.retry_after = retry_after


@dataclass
class FetchResult:
    status: int
    headers: dict
    body: bytes


def public_ip(address):
    try:
        ip = ipaddress.ip_address(address)
        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
            return public_ip(str(ip.ipv4_mapped))
        # Explicit ranges cover Python versions whose is_global tables differ.
        excluded = ("100.64.0.0/10", "192.0.0.0/24", "192.0.2.0/24", "198.18.0.0/15",
                    "198.51.100.0/24", "203.0.113.0/24", "64:ff9b::/96", "64:ff9b:1::/48", "2001::/23",
                    "2002::/16", "3fff::/20")
        return (ip.is_global and not (ip.is_multicast or ip.is_reserved or ip.is_unspecified
                                      or ip.is_loopback or ip.is_link_local or ip.is_private)
                and not any(ip in ipaddress.ip_network(net) for net in excluded
                                        if ip.version == ipaddress.ip_network(net).version)
                )
    except ValueError:
        return False


def _resolve_child(host, connection):
    try:
        values = sorted({row[4][0] for row in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)})
        connection.send(values)
    except Exception:
        connection.send([])
    finally:
        connection.close()


def resolve_public(host, timeout=4):
    # A subprocess can be stopped if libc DNS blocks; no immortal resolver threads.
    ctx = multiprocessing.get_context("spawn")
    receiver, sender = ctx.Pipe(duplex=False)
    process = ctx.Process(target=_resolve_child, args=(host, sender), daemon=True)
    process.start()
    sender.close()
    try:
        if not receiver.poll(timeout):
            raise FetchError("dns-timeout")
        addresses = receiver.recv()
        if not addresses or any(not public_ip(address) for address in addresses):
            raise FetchError("non-public-dns")
        return addresses
    finally:
        receiver.close()
        if process.is_alive():
            process.terminate()
        process.join(timeout=1)


def configured_url(url, source):
    if len(url) > 4096 or any(ord(char) < 33 or ord(char) == 127 for char in url) or "\\" in url:
        raise FetchError("invalid-feed-url")
    try:
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or parsed.hostname not in source["feedRedirectHosts"]
                or parsed.username is not None or parsed.password is not None
                or parsed.port not in (None, 443) or parsed.fragment):
            raise FetchError("unconfigured-feed-destination")
        return parsed
    except ValueError as exc:
        raise FetchError("invalid-feed-url") from exc


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, host, address, timeout):
        self.tls_context = ssl.create_default_context()
        self.tls_context.minimum_version = ssl.TLSVersion.TLSv1_2
        super().__init__(host, timeout=timeout, context=self.tls_context)
        self.address = address

    def connect(self):
        raw = socket.create_connection((self.address, 443), self.timeout)
        self.sock = raw
        try:
            # Connect to the vetted numeric address while verifying the original host.
            self.sock = self.tls_context.wrap_socket(raw, server_hostname=self.host,
                                                     do_handshake_on_connect=False)
            self.sock.do_handshake()
        except BaseException:
            raw.close()
            raise


def inflate_chunks(chunks, encoding="identity", deadline=None):
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS) if encoding == "gzip" else None
    if encoding not in ("gzip", "identity", ""):
        raise FetchError("unsupported-content-encoding")
    output = bytearray()
    wire = 0
    for chunk in chunks:
        if deadline is not None and time.monotonic() >= deadline:
            raise FetchError("deadline-exceeded")
        wire += len(chunk)
        if wire > MAX_WIRE_BYTES:
            raise FetchError("compressed-size-limit")
        if decoder:
            try:
                decoded = decoder.decompress(chunk, MAX_XML_BYTES + 1 - len(output))
            except zlib.error as exc:
                raise FetchError("invalid-gzip") from exc
            output.extend(decoded)
            if decoder.unconsumed_tail or decoder.unused_data:
                raise FetchError("decompression-size-or-stream-limit")
        else:
            output.extend(chunk)
        if len(output) > MAX_XML_BYTES:
            raise FetchError("xml-size-limit")
    if decoder and not decoder.eof:
        raise FetchError("truncated-gzip")
    return bytes(output)


class SecureFeedFetcher:
    accepted_types = XML_TYPES
    accept = "application/rss+xml, application/atom+xml, application/xml, text/xml"

    def checked_url(self, url, source):
        return configured_url(url, source)

    def __init__(self, resolver=resolve_public, connector=PinnedHTTPSConnection):
        self.resolver = resolver
        self.connector = connector

    def fetch(self, source, validators=None):
        # Callers only select a reviewed Source; no URL parameter is exposed.
        url = source["feedUrl"]
        deadline = time.monotonic() + FETCH_DEADLINE_SECONDS
        headers = {"User-Agent": "WingmanContent/1.0 (public RSS cache; no user data)",
                   "Accept": self.accept,
                   "Accept-Encoding": "gzip", "Connection": "close"}
        for key, value in (validators or {}).items():
            if key in ("If-None-Match", "If-Modified-Since") and isinstance(value, str):
                if len(value) <= 1024 and not any(ord(c) < 32 or ord(c) == 127 for c in value):
                    headers[key] = value
        for hop in range(MAX_REDIRECTS + 1):
            parsed = self.checked_url(url, source)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise FetchError("deadline-exceeded")
            addresses = self.resolver(parsed.hostname, min(4, remaining))
            if not addresses or any(not public_ip(address) for address in addresses):
                raise FetchError("non-public-dns")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise FetchError("deadline-exceeded")
            address = min(addresses, key=lambda value: ipaddress.ip_address(value).version)
            connection = self.connector(parsed.hostname, address, min(SOCKET_TIMEOUT_SECONDS, remaining))

            def interrupt():
                sock = connection.sock
                if sock:
                    try:
                        sock.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    sock.close()

            timer = threading.Timer(max(0.001, deadline - time.monotonic()), interrupt)
            timer.daemon = True
            timer.start()
            try:
                path = urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
                connection.request("GET", path, headers=headers)
                response = connection.getresponse()
                pairs = response.getheaders()
                if sum(len(k) + len(v) for k, v in pairs) > MAX_HEADERS_BYTES:
                    raise FetchError("header-size-limit")
                received = {}
                for key, value in pairs:
                    key = key.lower()
                    if key in received:
                        if key in ('cache-control', 'pragma', 'vary'):
                            received[key] += ', ' + value
                        elif key in ('content-type', 'content-length', 'content-encoding', 'location', 'retry-after', 'age'):
                            raise FetchError('duplicate-response-metadata')
                    else:
                        received[key] = value
                if response.status in (301, 302, 303, 307, 308):
                    if hop == MAX_REDIRECTS or not received.get("location"):
                        raise FetchError("redirect-limit")
                    url = urljoin(url, received["location"])
                    self.checked_url(url, source)
                    # Validators belong to a representation, not a new URL/host.
                    headers.pop("If-None-Match", None)
                    headers.pop("If-Modified-Since", None)
                    continue
                if response.status == 304:
                    return FetchResult(304, received, b"")
                if response.status != 200:
                    raise FetchError("http-%d" % response.status, received.get("retry-after"))
                if received.get("content-type", "").split(";")[0].strip().lower() not in self.accepted_types:
                    raise FetchError("unexpected-content-type")
                length = received.get("content-length")
                if length and (not length.isdigit() or int(length) > MAX_WIRE_BYTES):
                    raise FetchError("compressed-size-limit")
                body = inflate_chunks(iter(lambda: response.read(16384), b""),
                                      received.get("content-encoding", "identity").lower(), deadline)
                return FetchResult(200, received, body)
            except (OSError, http.client.HTTPException) as exc:
                raise FetchError("transport-error") from exc
            finally:
                timer.cancel()
                connection.close()
        raise FetchError("redirect-limit")
