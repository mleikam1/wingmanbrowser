import Foundation
import Darwin

/// IDNA utility only. No native live-content policy or legacy override remains.
final class NativeGuardPolicy {
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

}
