// Regenerates original provisional Wingman geometry using macOS AppKit.
// Run from repository root: swift scripts/generate_brand.swift
import AppKit
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func render(_ width: Int, _ relative: String) throws {
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let size = CGFloat(width)
  NSColor(srgbRed: 19/255, green: 95/255, blue: 81/255, alpha: 1).setFill()
  NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
  let points: [(CGFloat, CGFloat)] = [(0.18,0.34),(0.4,0.46),(0.79,0.24),(0.62,0.66),(0.47,0.77),(0.34,0.61)]
  let path = NSBezierPath()
  path.move(to: NSPoint(x: points[0].0*size, y: (1-points[0].1)*size))
  for point in points.dropFirst() { path.line(to: NSPoint(x: point.0*size, y: (1-point.1)*size)) }
  path.close()
  NSColor(srgbRed: 246/255, green: 201/255, blue: 105/255, alpha: 1).setFill()
  path.fill()
  let line = NSBezierPath()
  line.move(to: NSPoint(x: 0.4*size, y: 0.44*size))
  line.line(to: NSPoint(x: 0.67*size, y: 0.63*size))
  line.lineWidth = 0.035*size
  line.lineCapStyle = .round
  NSColor(srgbRed: 19/255, green: 95/255, blue: 81/255, alpha: 1).setStroke()
  line.stroke()
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(relative))
}
try render(1024, "assets/brand/wingman-mark.png")
for (directory, size) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
  try render(size, "android/app/src/main/res/mipmap-\(directory)/ic_launcher.png")
}
let iconDir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("\(iconDir)/Contents.json"))) as! [String: Any]
for record in contents["images"] as! [[String: Any]] {
  guard let filename = record["filename"] as? String, let size = record["size"] as? String, let scale = record["scale"] as? String else { continue }
  let side = Double(size.split(separator: "x")[0])! * Double(scale.dropLast())!
  try render(Int(side), "\(iconDir)/\(filename)")
}
try render(32, "web/favicon.png")
for size in [192,512] {
  try render(size, "web/icons/Icon-\(size).png")
  try render(size, "web/icons/Icon-maskable-\(size).png")
}
