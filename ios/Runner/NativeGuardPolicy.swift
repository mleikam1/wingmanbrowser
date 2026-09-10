import Foundation
import SQLite3
import WebKit
import CryptoKit
import Darwin

/// Local read-only indexed policy. It never contacts a classification service.
final class NativeGuardPolicy {
  private var database: OpaquePointer?
  private var databasePath: String?
  private(set) var configuration: [String: Any] = [:]
  private let lock = NSRecursiveLock()
  private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  deinit { if let database = database { sqlite3_close(database) } }

  func update(_ next: [String: Any]) throws {
    lock.lock(); defer { lock.unlock() }
    let path = next["databasePath"] as? String
    if path != databasePath {
      var replacement: OpaquePointer?
      if let path = path {
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(NSHomeDirectory() + "/"),
          sqlite3_open_v2(file.path, &replacement, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
          if let replacement = replacement { sqlite3_close(replacement) }
          throw GuardStorageError.unavailable
        }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(replacement, "SELECT active_generation,active_version FROM guard_state WHERE id=1", -1, &statement, nil)
        let valid = prepared == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW
        sqlite3_finalize(statement)
        guard valid else { sqlite3_close(replacement); throw GuardStorageError.unavailable }
        sqlite3_busy_timeout(replacement, 50)
      }
      if let database = database { sqlite3_close(database) }
      database = replacement; databasePath = path
    }
    configuration = next
  }

  private func strings(_ key: String) -> [String] { configuration[key] as? [String] ?? [] }
  private func matches(_ host: String, _ root: String) -> Bool { host == root || (!root.contains(":") && host.hasSuffix("." + root)) }
  private func matchesAny(_ host: String, _ roots: [String]) -> Bool { roots.contains { matches(host, $0) } }

  func evaluate(_ url: URL, tabId: String, filename: String? = nil, mimeType: String? = nil) -> [String: Any]? {
    lock.lock(); defer { lock.unlock() }
    guard ["http", "https"].contains(url.scheme ?? "") else { return nil }
    guard url.user == nil, url.password == nil, let rawHost = url.host, let host = Self.normalizeHost(rawHost) else {
      return ["action": "requireAdditionalCheck", "host": "", "ruleId": "invalid-domain", "overrideAllowed": false]
    }
    var rules: [(kind: String, category: String, id: String)] = []
    var version: String?
    var lookupFailed = false
    if let database = database {
      let labels = host.split(separator: ".")
      let numeric = host.range(of: "^[0-9.]+$", options: .regularExpression) != nil
      let suffixes = host.contains(":") || numeric ? [host] : (0..<(labels.count == 1 ? 1 : labels.count - 1)).map { labels[$0...].joined(separator: ".") }
      let placeholders = suffixes.map { _ in "?" }.joined(separator: ",")
      var statement: OpaquePointer?
      let sql = "SELECT r.host,r.kind,r.category,r.include_subdomains,r.rule_id,s.active_version FROM guard_rules r JOIN guard_state s ON r.generation=s.active_generation WHERE s.id=1 AND r.host IN (\(placeholders)) ORDER BY length(r.host) DESC,r.kind,r.category"
      if sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK {
        for (index, value) in suffixes.enumerated() {
          sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }
        func string(_ column: Int32) -> String {
          guard let value = sqlite3_column_text(statement, column) else { return "" }
          return String(cString: value)
        }
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
          if string(0) == host || sqlite3_column_int(statement, 3) == 1 {
            rules.append((string(1), string(2), string(4)))
            version = string(5)
          }
          step = sqlite3_step(statement)
        }
        lookupFailed = step != SQLITE_DONE
      } else { lookupFailed = true }
      sqlite3_finalize(statement)
      if lookupFailed { rules.removeAll() }
    }
    func blocked(_ action: String, category: String? = nil, id: String, security: Bool = false) -> [String: Any] {
      var decision: [String: Any] = ["action": action, "host": host, "ruleId": id,
        "overrideAllowed": !security && configuration["overridesLocked"] as? Bool != true]
      if let category = category { decision["category"] = category }
      if let version = version { decision["packVersion"] = version }
      return decision
    }
    if let rule = rules.first(where: { $0.kind == "malware" }) { return blocked("blockMalware", category: "malware", id: rule.id, security: true) }
    if let rule = rules.first(where: { $0.kind == "phishing" }) { return blocked("blockPhishing", category: "phishing", id: rule.id, security: true) }
    if filename != nil {
      if let rule = rules.first(where: { $0.kind == "harmful-download" }) { return blocked("blockHarmfulDownload", category: "harmful-downloads", id: rule.id, security: true) }

    }
    let grants = (configuration["allowOnce"] as? [String: [String]])?[tabId] ?? []
    let expires = (configuration["allowOnceExpires"] as? [String: [String: NSNumber]])?[tabId]?[host]?.doubleValue ?? 0
    let onceAllowed = configuration["overridesLocked"] as? Bool != true && grants.contains(host) && expires > Date().timeIntervalSince1970 * 1000
    let customBlock = strings("customBlock").filter { matches(host, $0) }.max { $0.count < $1.count }
    let customAllow = strings("customAllow").filter { matches(host, $0) }.max { $0.count < $1.count }
    if let customBlock = customBlock, (customAllow == nil || customBlock.count >= customAllow!.count) && !onceAllowed {
      return blocked("blockCustomRule", id: "custom-block")
    }
    if lookupFailed { return blocked("requireAdditionalCheck", id: "local-rules-unavailable", security: true) }
    if let filename = filename, configuration["blockHarmfulDownloads"] as? Bool == true && Self.riskyDownload(filename, mime: mimeType) {
      return blocked("requireAdditionalCheck", category: "harmful-downloads", id: "executable-download-type")
    }
    if customAllow != nil || onceAllowed { return nil }
    let focusUntil = (configuration["focusUntilEpochMs"] as? NSNumber)?.doubleValue ?? 0
    let focus = focusUntil > Date().timeIntervalSince1970 * 1000
    if focus && matchesAny(host, strings("focusHosts")) { return blocked("blockCustomRule", id: "focus-site") }
    if rules.contains(where: { $0.kind == "support" }) { return nil }
    let categories = configuration["guardEnabled"] as? Bool == true ? strings("enabledCategories") : []
    let focusCategories = focus ? strings("focusCategories") : []
    if let rule = rules.first(where: { $0.kind == "category" && (categories.contains($0.category) || focusCategories.contains($0.category)) }) {
      return blocked("blockCategory", category: rule.category, id: rule.id)
    }
    return nil
  }

  func safeSearch(_ url: URL) -> URL {
    guard configuration["guardEnabled"] as? Bool == true, strings("enabledCategories").contains("adult"),
      ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.port == nil || [80, 443].contains(url.port!),
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      var host = url.host?.lowercased() else { return url }
    if host.hasSuffix(".") { host.removeLast() }
    let target: (String, String, String)
    switch (host, url.path) {
    case let (h, p) where ["duckduckgo.com", "www.duckduckgo.com", "safe.duckduckgo.com", "html.duckduckgo.com", "lite.duckduckgo.com"].contains(h) && ["", "/", "/html", "/html/", "/lite", "/lite/"].contains(p): target = ("safe.duckduckgo.com", "kp", "1")
    case let (h, p) where ["google.com", "www.google.com"].contains(h) && p == "/search": target = (h, "safe", "active")
    case let (h, p) where ["bing.com", "www.bing.com"].contains(h) && ["/search", "/images/search", "/videos/search"].contains(p): target = (h, "adlt", "strict")
    case let (h, p) where ["search.brave.com", "safe.search.brave.com"].contains(h) && ["/search", "/images", "/videos", "/news", "/ask"].contains(p): target = ("safe.search.brave.com", "safesearch", "strict")
    default: return url
    }
    if url.scheme == "https" && url.port != 80 && url.host == target.0 && parts.queryItems?.filter({ $0.name == target.1 }).map({ $0.value ?? "" }) == [target.2] { return url }
    parts.host = target.0; parts.scheme = "https"; parts.port = nil
    parts.queryItems = (parts.queryItems ?? []).filter { $0.name != target.1 } + [URLQueryItem(name: target.1, value: target.2)]
    return parts.url ?? url
  }

  func trackingEnabled(for host: String) -> Bool {
    configuration["trackingEnabled"] as? Bool == true && !matchesAny(host, strings("trackingExceptions"))
  }

  static func normalizeHost(_ input: String) -> String? {
    guard !input.isEmpty, input.count <= 1024,
      input.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
      input.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\@?#%")) == nil else { return nil }
    var raw = input.lowercased()
    if raw.hasPrefix("[") && raw.hasSuffix("]") { raw.removeFirst(); raw.removeLast() }
    if raw.contains(":") {
      var address = in6_addr()
      guard inet_pton(AF_INET6, raw, &address) == 1 else { return nil }
      let bytes = withUnsafeBytes(of: address) { Array($0) }
      let words = stride(from: 0, to: 16, by: 2).map { Int(bytes[$0]) * 256 + Int(bytes[$0 + 1]) }
      var best = -1; var length = 1; var i = 0
      while i < 8 {
        if words[i] != 0 { i += 1; continue }
        let start = i
        while i < 8 && words[i] == 0 { i += 1 }
        if i - start > length { best = start; length = i - start }
      }
      if best < 0 { return words.map { String($0, radix: 16) }.joined(separator: ":") }
      return words.prefix(best).map { String($0, radix: 16) }.joined(separator: ":") + "::" + words.dropFirst(best + length).map { String($0, radix: 16) }.joined(separator: ":")
    }
    raw = raw.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".").replacingOccurrences(of: "｡", with: ".")
    if raw.hasSuffix(".") { raw.removeLast() }
    guard let host = URL(string: "https://\(raw)/")?.host?.lowercased() else { return nil }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard !host.isEmpty, host.utf8.count <= 253,
      host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) }),
      labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") &&
        !($0.count >= 4 && $0.dropFirst(2).prefix(2) == "--" && !$0.hasPrefix("xn--")) }) else { return nil }
    if labels.allSatisfy({ $0.range(of: "^([0-9]+|0x[0-9a-f]+)$", options: .regularExpression) != nil }) &&
      (labels.count != 4 || labels.contains(where: { $0.range(of: "^(0|[1-9][0-9]{0,2})$", options: .regularExpression) == nil || (Int($0) ?? 256) > 255 })) { return nil }
    return host
  }

  static func riskyDownload(_ filename: String, mime: String?) -> Bool {
    let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
    let executable = ["exe", "msi", "scr", "com", "bat", "cmd", "ps1", "vbs", "js", "jar", "apk", "aab", "dmg", "pkg", "app", "deb", "rpm"]
    let types = ["application/vnd.android.package-archive", "application/x-msdownload", "application/x-msi", "application/x-executable", "application/x-sh"]
    return executable.contains(ext) || types.contains(mime?.components(separatedBy: ";").first?.lowercased() ?? "")
  }
  enum GuardStorageError: Error { case unavailable }
}

/// Only the compiled licensed tracker list is persisted here, never site data.
final class GuardContentRules {
  private var current: WKContentRuleList?
  private var currentKey: String?

  func prepare(configuration: [String: Any], completion: @escaping (Error?) -> Void) {
    let domains = configuration["trackerDomains"] as? [String] ?? []
    let version = configuration["trackerVersion"] as? String ?? "starter"
    if domains.isEmpty { current = nil; currentKey = nil; completion(nil); return }
    let rules: [[String: Any]] = domains.map { domain in
      ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "\\.?[:/]",
        "load-type": ["third-party"]],
       "action": ["type": "block"]]
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
      let json = String(data: data, encoding: .utf8)!
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let key = "wingman-trackers-" + version + "-" + String(digest.prefix(16))
      if currentKey == key { completion(nil); return }
      WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: key) { [weak self] existing, _ in
        if let existing = existing {
          self?.current = existing; self?.currentKey = key; completion(nil); return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: key, encodedContentRuleList: json) { [weak self] compiled, error in
          if let compiled = compiled {
            self?.current = compiled; self?.currentKey = key
            WKContentRuleListStore.default().getAvailableContentRuleListIdentifiers { identifiers in
              for identifier in identifiers ?? [] where identifier.hasPrefix("wingman-trackers-") && identifier != key {
                WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { _ in }
              }
            }
          }
          completion(error)
        }
      }
    } catch { completion(error) }
  }

  func apply(to webView: WKWebView, enabled: Bool) {
    webView.configuration.userContentController.removeAllContentRuleLists()
    if enabled, let current = current { webView.configuration.userContentController.add(current) }
  }
}
