import Foundation
import WebKit
import CryptoKit

// Shared by iOS and macOS: one policy, canonicalization and signed-update implementation.
/// Playback suspension alone does not stop microphone/camera capture. Hidden
/// tabs and inactive scenes must end capture and dismiss fullscreen/PiP too.
/// Returning to the tab resumes playback eligibility, never a capture grant.
func consumerSetWebActivity(_ web: WKWebView, allowed: Bool) {
  web.setAllMediaPlaybackSuspended(!allowed)
  if !allowed {
    web.setCameraCaptureState(.none, completionHandler: nil)
    web.setMicrophoneCaptureState(.none, completionHandler: nil)
    web.closeAllMediaPresentations(completionHandler: nil)
  }
}

/// A deliberate WebKit policy cancellation is not a network/TLS failure.
func consumerExpectedNavigationCancellation(_ error: NSError, policyCancellationExpected: Bool) -> Bool {
  (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) ||
    (policyCancellationExpected && error.domain == "WebKitErrorDomain" && error.code == 102)
}

func consumerWebConfiguration(privateMode: Bool, rules: [WKContentRuleList]) -> WKWebViewConfiguration {
  let configuration = WKWebViewConfiguration()
  configuration.websiteDataStore = privateMode ? .nonPersistent() : .default()
  configuration.defaultWebpagePreferences.allowsContentJavaScript = true
  configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
  configuration.preferences.isFraudulentWebsiteWarningEnabled = true
  #if os(iOS)
  if #available(iOS 15.4, *) { configuration.preferences.isElementFullscreenEnabled = true }
  configuration.allowsInlineMediaPlayback = true
  #else
  configuration.preferences.isElementFullscreenEnabled = true
  #endif
  configuration.mediaTypesRequiringUserActionForPlayback = .all
  for rule in rules { configuration.userContentController.add(rule) }
  return configuration
}

func consumerOrigin(_ raw: String) -> String? {
  guard let components = URLComponents(string: raw), let scheme = components.scheme, let host = components.host else { return nil }
  return "\(scheme.lowercased())://\(host.lowercased()):\(components.port ?? (scheme == "https" ? 443 : 80))"
}

func consumerBaselineDomain(_ host: String) -> Bool {
  let bytes = host.utf8
  guard !bytes.isEmpty, bytes.count <= 253,
    bytes.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }) else { return false }
  return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
    !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
  }
}

/// Restoring the acknowledged active release must not erase its predecessor.
func consumerActivationReceipt(currentSequence: Int, currentDigest: String, previous: [String: Any]?, sequence: Int, digest: String, highWater: Int) -> [String: Any] {
  let restoringCurrent = currentSequence == sequence && currentDigest == digest
  let prior = restoringCurrent ? previous : nil
  return ["sequence": sequence, "sha256": digest, "highest": max(highWater, sequence),
    "previous": prior ?? ["sequence": currentSequence, "sha256": currentDigest]]
}

enum ConsumerNativeUpdateError: Error { case invalid }

/// Update trust roots are shipped only in the signed application bundle. The
/// production asset intentionally has no keys until a real feed is provisioned.
final class ConsumerNativeUpdate {
  let token = UUID().uuidString
  let sequence: Int
  let digest: String
  let policy: ConsumerNativePolicy
  let envelope: Data
  let data: Data
  var rules: [WKContentRuleList] = []
  var prepared = false
  init(envelope: Data, data: Data, keys: [String: String]) throws {
    guard envelope.count <= 64 * 1024, !data.isEmpty, data.count <= 16 * 1024 * 1024,
      let outer = (try? JSONSerialization.jsonObject(with: envelope)) as? [String: Any], outer.count == 3,
      let keyID = outer["keyId"] as? String, let encodedKey = keys[keyID], let keyData = Data(base64Encoded: encodedKey), keyData.count == 32,
      let encodedPayload = outer["payload"] as? String, let payload = Data(base64Encoded: encodedPayload),
      let encodedSignature = outer["signature"] as? String, let signature = Data(base64Encoded: encodedSignature), signature.count == 64,
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData), key.isValidSignature(signature, for: payload),
      let meta = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
      meta["purpose"] as? String == "wingman-consumer-protection-v1", meta["schemaVersion"] as? Int == 1,
      let sequence = meta["sequence"] as? Int, (2...2147483647).contains(sequence),
      let version = meta["version"] as? String, version.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._+-]{0,79}$", options: .regularExpression) != nil,
      let generated = meta["generatedAt"] as? String, generated.hasSuffix("Z"), let generatedDate = consumerISODate(generated), generatedDate <= Date().addingTimeInterval(86400),
      let minimum = meta["minimumAppVersion"] as? String,
      consumerAppVersionSupported(minimum), meta["filename"] as? String == "consumer-\(sequence).json",
      meta["bytes"] as? Int == data.count, let digest = meta["sha256"] as? String,
      digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest,
      let license = meta["license"] as? String, !license.isEmpty, license.count <= 4096,
      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], body["sequence"] as? Int == sequence,
      body["version"] as? String == version, body["generatedAt"] as? String == generated else { throw ConsumerNativeUpdateError.invalid }
    let policy = ConsumerNativePolicy(data: data, expectedDigest: digest)
    guard policy.valid else { throw ConsumerNativeUpdateError.invalid }
    self.sequence = sequence; self.digest = digest; self.policy = policy; self.envelope = envelope; self.data = data
  }
  static func directory() throws -> URL {
    var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wingman/ConsumerPolicies", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
    return directory
  }
  static func receipt() throws -> [String: Any] {
    let url = try directory().appendingPathComponent("receipt.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let bytes = try Data(contentsOf: url)
    guard bytes.count <= 16384, let receipt = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
      let sequence = receipt["sequence"] as? Int, (1...2147483647).contains(sequence),
      let highest = receipt["highest"] as? Int, highest >= sequence, highest <= 2147483647,
      let digest = receipt["sha256"] as? String, digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ConsumerNativeUpdateError.invalid }
    if let previous = receipt["previous"] as? [String: Any] {
      guard let priorSequence = previous["sequence"] as? Int, (1...highest).contains(priorSequence),
        let priorDigest = previous["sha256"] as? String, priorDigest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ConsumerNativeUpdateError.invalid }
    }
    return receipt
  }
  static func prune(receipts: [[String: Any]]) {
    var retained = Set<String>()
    for receipt in receipts {
      if let digest = receipt["sha256"] as? String { retained.insert(digest) }
      if let prior = receipt["previous"] as? [String: Any], let digest = prior["sha256"] as? String { retained.insert(digest) }
    }
    guard let directory = try? directory(), let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
    for file in files where file.lastPathComponent.range(of: "^[0-9a-f]{64}\\.json$", options: .regularExpression) != nil && !retained.contains(file.deletingPathExtension().lastPathComponent) {
      try? FileManager.default.removeItem(at: file)
    }
  }
  func persist() throws {
    let package: [String: Any] = ["envelope": envelope.base64EncodedString(), "data": data.base64EncodedString()]
    try JSONSerialization.data(withJSONObject: package).write(to: Self.directory().appendingPathComponent(digest + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

func consumerISODate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter()
  if let date = formatter.date(from: value) { return date }
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: value)
}

func consumerAppVersionSupported(_ minimum: String) -> Bool {
  let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.10.0"
  func parts(_ value: String) -> [Int]? {
    guard value.range(of: "^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$", options: .regularExpression) != nil else { return nil }
    let values = value.split(separator: ".", omittingEmptySubsequences: false)
    guard values.count == 3 else { return nil }
    let parsed = values.compactMap { Int($0) }
    return parsed.count == 3 && parsed.allSatisfy { $0 >= 0 } ? parsed : nil
  }
  guard let required = parts(minimum), let actual = parts(current) else { return false }
  for i in 0..<3 { if actual[i] != required[i] { return actual[i] > required[i] } }
  return true
}

enum ConsumerNativeReasonCode: String {
  case blockMandatoryCategory, blockSecurityThreat, blockAdditionalRestriction, blockPolicyUnavailable, blockUnsupportedCapability
}

struct ConsumerNativeDecision {
  let url: URL?
  let reason: String
  let reasonCode: ConsumerNativeReasonCode
  let category: String?
  init(_ url: URL? = nil, _ reason: String = "This browser operation is unavailable.",
    reasonCode: ConsumerNativeReasonCode = .blockUnsupportedCapability, category: String? = nil) {
    self.url = url; self.reason = reason; self.reasonCode = reasonCode; self.category = category
  }
}

/// Pinned baseline or independently verified signed update. Classification is
/// local; no browsing URLs are sent to a policy service.
final class ConsumerNativePolicy {
  private(set) var valid = false
  private var domains: [String: String] = [:]
  private var pathRules: [(host: String, path: String, category: String)] = []
  private var trackers: [String] = []
  var domainCount: Int { domains.count }
  init(path: String?, expectedDigest: String) {
    guard let path = path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
    load(data: data, expectedDigest: expectedDigest)
  }
  init(data: Data, expectedDigest: String) { load(data: data, expectedDigest: expectedDigest) }
  private func load(data: Data, expectedDigest: String) {
    guard !data.isEmpty, data.count <= 16 * 1024 * 1024, String(data: data, encoding: .utf8) != nil, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedDigest,
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      json["schemaVersion"] as? Int == 1, (json["sequence"] as? Int ?? 0) >= 1,
      let categories = json["categories"] as? [String: [String]], categories.count == 6,
      let paths = json["pathRules"] as? [[String: String]], let trackerEntries = json["trackers"] as? [String] else { return }
    for category in ["sexual-explicit", "gambling", "alcohol-promotion", "recreational-drug-promotion", "tobacco-nicotine", "security-threat"] {
      guard let entries = categories[category], !entries.isEmpty, entries.count <= 500000 else { return }
      for host in entries { guard consumerBaselineDomain(host) else { return }; domains[host] = category }
    }
    for row in paths {
      guard let host = row["host"], NativeGuardPolicy.normalizeHost(host) == host,
        let path = row["pathPrefix"], path.hasPrefix("/"), !path.contains("%"), !path.contains("?"), path == path.lowercased(),
        let category = row["category"], categories[category] != nil else { return }
      pathRules.append((host, path.lowercased(), category))
    }
    guard trackerEntries.allSatisfy({ consumerBaselineDomain($0) }) else { return }
    trackers = trackerEntries
    valid = true
  }
  func check(_ input: String) -> ConsumerNativeDecision {
    guard valid else { return ConsumerNativeDecision(nil, "Mandatory protection data is unavailable. Recovery is required.", reasonCode: .blockPolicyUnavailable) }
    guard let url = consumerCheckedURL(input) else { return ConsumerNativeDecision(nil, "This address is unsupported or contains credentials.") }
    guard let target = consumerSearchDestination(url) else { return ConsumerNativeDecision(nil, "This search shortcut or provider address cannot enforce strict search.") }
    guard let host = target.host?.lowercased() else { return ConsumerNativeDecision() }
    var candidate = host
    while true {
      if let category = domains[candidate] { return ConsumerNativeDecision(nil, "Blocked category: \(category).", reasonCode: category == "security-threat" ? .blockSecurityThreat : .blockMandatoryCategory, category: category) }
      guard let dot = candidate.firstIndex(of: ".") else { break }; candidate = String(candidate[candidate.index(after: dot)...])
    }
    var pathSegments: [String] = []
    let decodedPath = URLComponents(url: target, resolvingAgainstBaseURL: false)?.percentEncodedPath.removingPercentEncoding ?? target.path
    for segment in decodedPath.lowercased().split(separator: "/") {
      if segment == ".." { if !pathSegments.isEmpty { pathSegments.removeLast() } }
      else if segment != "." { pathSegments.append(String(segment)) }
    }
    let path = "/" + pathSegments.joined(separator: "/")
    for rule in pathRules where host == rule.host || host.hasSuffix("." + rule.host) {
      if path == rule.path || path.hasPrefix(rule.path.hasSuffix("/") ? rule.path : rule.path + "/") { return ConsumerNativeDecision(nil, "Blocked category: \(rule.category).", reasonCode: rule.category == "security-threat" ? .blockSecurityThreat : .blockMandatoryCategory, category: rule.category) }
      if consumerHasAmbiguousPathEncoding(target) {
        return ConsumerNativeDecision(nil, "This site's encoded address cannot be checked safely. Use its standard address.")
      }
    }
    return ConsumerNativeDecision(target)
  }
  func contentRuleGroups() -> [String] {
    var rules: [[String: Any]] = []
    for domain in domains.keys.sorted() {
      rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]"], "action": ["type": "block"]])
    }
    var groups: [String] = stride(from: 0, to: rules.count, by: 25000).compactMap { start in
      guard let data = try? JSONSerialization.data(withJSONObject: Array(rules[start..<min(start + 25000, rules.count)])) else { return nil }
      return String(data: data, encoding: .utf8)
    }
    rules.removeAll(keepingCapacity: false)
    for rule in pathRules {
      let prefix = "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: rule.host) + "(:[0-9]+)?" + consumerContentRulePath(rule.path)
      rules.append(["trigger": ["url-filter": prefix + "$"], "action": ["type": "block"]])
      rules.append(["trigger": ["url-filter": prefix + "[/?#]"], "action": ["type": "block"]])
    }
    // WKContentRuleList does not canonicalize encoded ASCII path characters
    // and cannot express alternation. Only hosts with mandatory path rules
    // reject these ambiguous spellings; queries, spaces and UTF-8 stay usable.
    for host in Set(pathRules.map { $0.host }) {
      let prefix = "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: host) + "(:[0-9]+)?/[^?#]*"
      for encoded in consumerAmbiguousPathPatterns {
        rules.append(["trigger": ["url-filter": prefix + encoded], "action": ["type": "block"]])
      }
    }
    for domain in trackers {
      rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]", "load-type": ["third-party"]], "action": ["type": "block"]])
    }
    rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?duckduckgo\\.com\\.?/ac[/?#]"], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": "^https?://([^/]+\\.)?duckduckgo\\.com\\.?/ac$"], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": "^https?://[^/]*@"], "action": ["type": "block"]])
    rules.append(["trigger": ["url-filter": "^https?://[^/]+\\.[/:]"], "action": ["type": "block"]])
    if let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) { groups.append(json) }
    return groups
  }
}

/// Domain rules are unchanged. Invalidate only the final path/tracker group so
/// an upgrade cannot reuse literal-path rules without recompiling all domains.
func consumerContentRuleIdentifier(digest: String, index: Int, count: Int) -> String {
  "wingman-consumer-\(index == count - 1 ? "v7" : "v5")-\(digest)-\(index)"
}

// Percent encodings of ASCII letters, digits, '-', '.', '_', '~' or '/'.
// Each expression belongs to WebKit's supported regex subset (no alternation).
let consumerAmbiguousPathPatterns = ["%3[0-9]", "%[46][1-9a-f]", "%[57][0-9a]", "%2[d-f]", "%5f", "%7e"]
func consumerHasAmbiguousPathEncoding(_ url: URL) -> Bool {
  guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
  return consumerAmbiguousPathPatterns.contains { path.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
}

/// WebKit's content-blocker regex subset supports repetition but not `|`.
/// Repeated literal path separators must not evade the pinned path prefix.
func consumerContentRulePath(_ path: String) -> String {
  "/+" + path.split(separator: "/").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "/+")
}

func consumerCheckedURL(_ input: String) -> URL? {
  guard !input.isEmpty, input.utf8.count <= 16384, !input.contains("\\"),
    input.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
    var components = URLComponents(string: input), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
    components.user == nil, components.password == nil,
    components.port == nil || (1...65535).contains(components.port!),
    input.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*%", options: .regularExpression) == nil,
    input.range(of: "%(00|0a|0d)", options: [.regularExpression, .caseInsensitive]) == nil,
    input.range(of: "%(?![0-9a-fA-F]{2})", options: .regularExpression) == nil,
    let rawHost = components.host,
    let host = NativeGuardPolicy.normalizeHost(rawHost) else { return nil }
  components.scheme = components.scheme?.lowercased(); components.host = host
  if components.path.isEmpty { components.path = "/" }
  return components.url
}

func strictSearchURL(_ query: String) -> String? {
  guard let value = consumerSearchQuery(query) else { return nil }
  var components = URLComponents(string: "https://safe.duckduckgo.com/")!
  components.percentEncodedQuery = "q=" + consumerQueryEncode(value) + "&kp=1&kac=-1"
  return components.url?.absoluteString
}


func consumerQueryEncode(_ value: String) -> String {
  value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
}
func consumerQueryItems(_ components: URLComponents) -> [URLQueryItem]? {
  guard let encoded = components.percentEncodedQuery, !encoded.isEmpty else { return [] }
  var result: [URLQueryItem] = []
  for part in encoded.split(separator: "&", omittingEmptySubsequences: false) {
    guard let separator = part.firstIndex(of: "=") else { return nil }
    let keyText = String(part[..<separator]).replacingOccurrences(of: "+", with: "%20")
    let valueText = String(part[part.index(after: separator)...]).replacingOccurrences(of: "+", with: "%20")
    guard let key = keyText.removingPercentEncoding, !key.isEmpty,
      key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
      let value = valueText.removingPercentEncoding else { return nil }
    result.append(URLQueryItem(name: key, value: value))
  }
  return result
}

func consumerSearchQuery(_ input: String) -> String? {
  guard input.utf16.count <= 8192 else { return nil }
  func control(_ value: UInt32) -> Bool {
    value <= 0x1f || (0x7f...0x9f).contains(value) || value == 0x061c || value == 0x200e || value == 0x200f || (0x2028...0x202e).contains(value) || (0x2066...0x2069).contains(value)
  }
  func trimSpace(_ value: UInt32) -> Bool {
    value == 0x20 || value == 0xa0 || value == 0x1680 || (0x2000...0x200a).contains(value) || value == 0x202f || value == 0x205f || value == 0x3000 || value == 0xfeff
  }
  let scalars = Array(input.unicodeScalars)
  guard !scalars.contains(where: { control($0.value) }) else { return nil }
  var start = 0
  var end = scalars.count
  while start < end && trimSpace(scalars[start].value) { start += 1 }
  while end > start && trimSpace(scalars[end - 1].value) { end -= 1 }
  guard (1...512).contains(end - start) else { return nil }
  let value = String(String.UnicodeScalarView(scalars[start..<end]))
  let bytes = Array(value.utf8)
  guard bytes.count <= 1024, let encodedRun = try? NSRegularExpression(pattern: "(?:%[0-9a-fA-F]{2})+") else { return nil }
  var probe = value
  for round in 0...8 {
    probe = String(String.UnicodeScalarView(probe.unicodeScalars.map { scalar in
      let code = scalar.value
      return UnicodeScalar((0xff01...0xff5e).contains(code) ? code - 0xfee0 : code == 0xfe57 ? 0x21 : code == 0xfe68 ? 0x5c : code)!
    }))
    guard !probe.unicodeScalars.contains(where: { control($0.value) }),
      !probe.hasPrefix("\\"), probe.range(of: "(^|[^a-zA-Z0-9_])![a-zA-Z0-9_]", options: .regularExpression) == nil else { return nil }
    let matches = encodedRun.matches(in: probe, range: NSRange(probe.startIndex..., in: probe))
    if matches.isEmpty { return value }
    guard round < 8 else { return nil }
    for match in matches.reversed() {
      guard let range = Range(match.range, in: probe) else { return nil }
      let encoded = Array(probe[range].utf8)
      var decoded = [UInt8]()
      for index in stride(from: 0, to: encoded.count, by: 3) {
        guard let byte = UInt8(String(decoding: encoded[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) else { return nil }
        decoded.append(byte)
      }
      guard let replacement = String(bytes: decoded, encoding: .utf8) else { return nil }
      probe.replaceSubrange(range, with: replacement)
    }
  }
  return nil
}


/// Only known provider navigation endpoints are rewritten. Search resources
/// keep normal cookies, CSS, scripts and pagination. No provider HTML scraping.
func consumerSearchDestination(_ url: URL) -> URL? {
  guard let host = url.host?.lowercased(), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
  let duckHosts: Set<String> = ["duckduckgo.com", "www.duckduckgo.com", "safe.duckduckgo.com", "html.duckduckgo.com", "lite.duckduckgo.com", "noai.duckduckgo.com", "start.duckduckgo.com", "duck.com", "www.duck.com", "ddg.gg"]
  let ddgRelated = host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com") || duckHosts.contains(host)
  if ddgRelated || ["google.com", "www.google.com", "bing.com", "www.bing.com", "search.brave.com", "safe.search.brave.com"].contains(host) {
    guard components.port == nil || components.port == (url.scheme == "https" ? 443 : 80),
      !components.percentEncodedPath.contains("%"), !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
    if ["/", "/html", "/html/", "/lite", "/lite/"].contains(components.path) && ddgRelated && !duckHosts.contains(host) { return nil }
  }
  let knownSearch = duckHosts.contains(host) && ["/", "/html", "/html/", "/lite", "/lite/"].contains(url.path)
  let alternative = (["google.com", "www.google.com"].contains(host) && ["/search", "/"].contains(url.path)) ||
    (["bing.com", "www.bing.com"].contains(host) && ["/search", "/", "/images/search", "/videos/search"].contains(url.path)) ||
    (["search.brave.com", "safe.search.brave.com"].contains(host) && ["/search", "/", "/images", "/videos", "/news", "/ask"].contains(url.path))
  if duckHosts.contains(host), components.path == "/l/" {
    guard let items = consumerQueryItems(components) else { return nil }
    guard url.scheme == "https", components.port == nil, components.fragment == nil,
      Set(items.map { $0.name }).count == items.count,
      items.filter({ $0.name == "uddg" }).count == 1, items.allSatisfy({ ["uddg", "rut"].contains($0.name) }),
      items.first(where: { $0.name == "rut" })?.value?.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil || !items.contains(where: { $0.name == "rut" }),
      let raw = items.first(where: { $0.name == "uddg" })?.value, raw.utf8.count <= 4096, let target = consumerCheckedURL(raw), target.scheme == "https", URLComponents(url: target, resolvingAgainstBaseURL: false)?.port == nil,
      !(duckHosts.contains(target.host ?? "") && URLComponents(url: target, resolvingAgainstBaseURL: false)?.path == "/l/") else { return nil }
    return consumerSearchDestination(target)
  }
  guard knownSearch || alternative else { return url }
  guard var items = consumerQueryItems(components) else { return nil }
  guard Set(items.map { $0.name }).count == items.count, !items.contains(where: { $0.name.lowercased() == "q" && $0.name != "q" }) else { return nil }
  let query = items.first(where: { $0.name == "q" })?.value
  if let query = query {
    guard let value = consumerSearchQuery(query), let index = items.firstIndex(where: { $0.name == "q" }) else { return nil }
    items[index] = URLQueryItem(name: "q", value: value)
  }
  if alternative {
    if query == nil { return URL(string: "https://safe.duckduckgo.com/?kp=1&kac=-1") }
    guard let raw = strictSearchURL(query!) else { return nil }; return URL(string: raw)
  }
  components.scheme = "https"; components.host = "safe.duckduckgo.com"; components.port = nil; components.fragment = nil
  // HTML/lite pagination can use provider POST; retaining the endpoint keeps
  // ordinary refinement and subsequent results, with strict host enforcement.
  components.percentEncodedQuery = (items.filter { !["kp", "kac"].contains($0.name.lowercased()) } + [URLQueryItem(name: "kp", value: "1"), URLQueryItem(name: "kac", value: "-1")]).map { consumerQueryEncode($0.name) + "=" + consumerQueryEncode($0.value ?? "") }.joined(separator: "&")
  if query == nil && items.isEmpty { components.percentEncodedQuery = "kp=1&kac=-1" }
  return components.url
}

// Legacy restricted-reader rule helpers. These are never used by consumer views.
/// Pure rule construction is independently exercised by the native XCTest target.
/// Production callers supply only the hash-pinned catalog; this is not a platform channel.
func protectedContentRuleJSON(documents: [String], resources: [String: String], privacyDomains: [String]) -> String? {
  var rules: [[String: Any]] = [["trigger": ["url-filter": ".*"], "action": ["type": "block"]]]
  var entries = resources
  for url in documents { entries[url] = "document" }
  for (url, kind) in entries.sorted(by: { $0.key < $1.key }) {
    let type = kind == "styleSheet" ? "style-sheet" : kind
    rules.append(["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: url) + "$", "url-filter-is-case-sensitive": true, "resource-type": [type]], "action": ["type": "ignore-previous-rules"]])
  }
  // A maintained deny-only list cannot grant permission to any destination.
  for domain in privacyDomains.sorted() {
    rules.append(["trigger": ["url-filter": "^https://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]", "load-type": ["third-party"]], "action": ["type": "block"]])
  }
  rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]])
  // Scriptless reading has no supported editable forms; hide focusable editors before interaction.
  rules.append(["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "input,textarea,select,[contenteditable]"]])
  guard let bytes = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: bytes, encoding: .utf8) else { return nil }
  return json

}
func protectedDate(_ input: Any?) -> Date? {
  guard let value = input as? String else { return nil }
  return ISO8601DateFormatter().date(from: value)
}
func protectedCanonical(_ raw: String) -> String? {
  guard !raw.isEmpty, raw.utf8.count <= 16_384, raw.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 && $0 != "\\" }),
    var components = URLComponents(string: raw), components.scheme == "https", components.user == nil, components.password == nil,
    components.port == nil, let host = components.host, !host.isEmpty, host == host.lowercased(), !host.hasSuffix("."),
    components.percentEncodedPath.range(of: "%(00|0a|0d|2f|5c)", options: .regularExpression.union(.caseInsensitive)) == nil, !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
  components.fragment = nil
  if components.path.isEmpty { components.path = "/" }
  return components.string
}

let strictSearchCSS = "https://safe.duckduckgo.com/dist/lr.48ddfe4eadf6a534e93f.css"

/// No page/query-derived rules are written to WebKit's persistent rule store.
func strictSearchContentRuleJSON(documentOrigin: String = "https://safe.duckduckgo.com", styleURL: String = "https://safe.duckduckgo.com/dist/lr.48ddfe4eadf6a534e93f.css") -> String? {
  let rules: [[String: Any]] = [
    ["trigger": ["url-filter": ".*"], "action": ["type": "block"]],
    ["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: documentOrigin) + "/lite/\\?q=[A-Za-z0-9._~%\\-]+&kp=1$", "url-filter-is-case-sensitive": true, "resource-type": ["document"]], "action": ["type": "ignore-previous-rules"]],
    ["trigger": ["url-filter": "^" + NSRegularExpression.escapedPattern(for: styleURL) + "$", "url-filter-is-case-sensitive": true, "resource-type": ["style-sheet"]], "action": ["type": "ignore-previous-rules"]],
    ["trigger": ["url-filter": ".*"], "action": ["type": "block-cookies"]],
    ["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": "input,textarea,select,[contenteditable]"]],
  ]
  guard let bytes = try? JSONSerialization.data(withJSONObject: rules) else { return nil }
  return String(data: bytes, encoding: .utf8)
}

/// Shared with the owned WebKit fixture. Resource rules alone do not grant
/// navigation: only the explicitly opened, current top-level GET may proceed.
func protectedAllowsInitialNavigation(isMainFrame: Bool, method: String?, requestedURL: String, currentURL: String, initial: Bool, scopePermitted: Bool) -> Bool {
  isMainFrame && method == "GET" && initial && scopePermitted && requestedURL == currentURL
}
