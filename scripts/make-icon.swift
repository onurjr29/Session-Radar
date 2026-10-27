// Uygulama ikonunu CoreGraphics ile çizer ve Resources/ altına yazar:
//   Resources/AppIcon.icns  — klasik ikon (macOS ızgarası: 1024 tuval, 824 gövde, sürekli köşe, gölge)
//   Resources/AppIcon.icon  — macOS 26+ için Icon Composer paketi (arka plan sistemin dolgusu, katmanlar cam)
// Kullanım: swift scripts/make-icon.swift [--preview KLASÖR]
// Çıktılar repoya girer; normal derleme bu betiği çalıştırmaz.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func white(_ a: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

// Uygulamadaki durum renkleri (koyu mod sistem tonları): çalışıyor, bekliyor, bitti.
let blue = rgb(0x0A84FF), orange = rgb(0xFF9F0A), green = rgb(0x30D158)
let bgTop = rgb(0x3D8BFF), bgBottom = rgb(0x0B2E8C)

// MARK: Şekil

/// Apple'ın "sürekli" köşeli kare gövdesi: köşeler çeyrek süper elips (kenar boyunca 1.528·r),
/// 45°'de dairesel r köşesiyle aynı noktadan geçer; kenara eğrilik sıfırla bağlanır.
func squircle(_ rect: CGRect, radius r: CGFloat) -> CGPath {
    let R = 1.528665 * r
    let n = log(2) / -log(1 - r * (1 - 1 / sqrt(2)) / R)
    let centers = [CGPoint(x: rect.maxX - R, y: rect.maxY - R), CGPoint(x: rect.minX + R, y: rect.maxY - R),
                   CGPoint(x: rect.minX + R, y: rect.minY + R), CGPoint(x: rect.maxX - R, y: rect.minY + R)]
    let path = CGMutablePath()
    for (i, c) in centers.enumerated() {
        for step in 0...48 {
            let t = (CGFloat(i) + CGFloat(step) / 48) * .pi / 2
            let (co, si) = (cos(t), sin(t))
            let p = CGPoint(x: c.x + R * copysign(pow(abs(co), 2 / n), co), y: c.y + R * copysign(pow(abs(si), 2 / n), si))
            i == 0 && step == 0 ? path.move(to: p) : path.addLine(to: p)
        }
    }
    path.closeSubpath()
    return path
}

// MARK: Çizim (gövde birimi: gövde 1024×1024 kare, y yukarı)

let center = CGPoint(x: 512, y: 512)
let lead: CGFloat = 50 * .pi / 180          // tarama kolunun açısı; saat yönünde döner, iz arkasında (artan açı)
let trailSpan: CGFloat = 90 * .pi / 180
let outer: CGFloat = 400

struct Detail {
    let px: CGFloat                          // bir gövde biriminin piksel karşılığı
    var small: Bool { px * 1024 < 40 }       // 16 ve 32 piksel ikonlar: daha az halka, kalın çizgi
    var tiny: Bool { px * 1024 < 20 }        // 16 piksel: tek halka, çerçevesiz iki nokta
    func w(_ design: CGFloat, minPx: CGFloat) -> CGFloat { max(design, minPx / px) }
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }
func polar(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
    CGPoint(x: center.x + r * cos(deg * .pi / 180), y: center.y + r * sin(deg * .pi / 180))
}

func drawBackground(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: srgb, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
    let glow = CGGradient(colorsSpace: srgb, colors: [rgb(0x7FC0FF, 0.35), rgb(0x7FC0FF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 470, options: [])
}

func drawRings(_ ctx: CGContext, _ d: Detail) {
    let radii: [CGFloat] = d.tiny ? [outer] : d.small ? [230, outer] : [145, 272, outer]
    ctx.setStrokeColor(white(d.small ? 0.6 : 0.42))
    ctx.setLineWidth(d.w(13, minPx: 1.1))
    for r in radii { ctx.strokeEllipse(in: circle(center, r)) }
}

func drawSweep(_ ctx: CGContext, _ d: Detail) {
    // Yumuşak iz: konik degrade, kolda en parlak, geriye doğru söner.
    ctx.saveGState()
    ctx.addEllipse(in: circle(center, outer))
    ctx.clip()
    let f = trailSpan / (2 * .pi)
    let a: CGFloat = d.small ? 0.5 : 0.48
    let g = CGGradient(colorsSpace: srgb,
                       colors: [white(a), white(a * 0.6), white(a * 0.25), white(0), white(0)] as CFArray,
                       locations: [0, f * 0.25, f * 0.6, f, 1])!
    CGContextDrawConicGradient(ctx, g, center, lead)
    ctx.restoreGState()

    ctx.setStrokeColor(white(0.95))
    ctx.setLineCap(.round)
    ctx.setLineWidth(d.w(15, minPx: 1.2))
    ctx.move(to: center)
    ctx.addLine(to: polar(outer, lead * 180 / .pi))
    ctx.strokePath()
    ctx.setFillColor(white(1))
    ctx.fillEllipse(in: circle(center, d.w(30, minPx: 1.1)))
}

func drawDots(_ ctx: CGContext, _ d: Detail) {
    // İz içinde yeni yakalanmış "çalışıyor", dış halkada "bekliyor", iç halkada "bitti".
    // 16 pikselde mavi nokta mavi zeminde kaybolur; yalnız turuncu ve yeşil kalır.
    let dots: [(CGFloat, CGFloat, CGColor)] = d.tiny
        ? [(outer, 215, orange), (250, 320, green)]
        : d.small
        ? [(230, 95, blue), (outer, 215, orange), (230, 320, green)]
        : [(272, 92, blue), (outer, 212, orange), (145, 318, green)]
    let r = d.w(40, minPx: 1.5), rim = d.tiny ? 0 : d.w(9, minPx: 0.5)
    for (dist, deg, color) in dots {
        let p = polar(dist, deg)
        ctx.setFillColor(white(1))
        if rim > 0 { ctx.fillEllipse(in: circle(p, r + rim)) }
        ctx.setFillColor(color)
        ctx.fillEllipse(in: circle(p, r))
    }
}

// MARK: Görüntü üretimi

func render(_ size: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

/// Klasik macOS ikonu: 1024 tuvalde 100 pt içeride 824×824 gövde, köşe yarıçapı 185.4, yumuşak gölge.
func classicIcon(_ size: Int) -> CGImage {
    render(size) { ctx in
        let s = CGFloat(size) / 1024
        ctx.scaleBy(x: s, y: s)
        let body = squircle(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185.4)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 22 * s, color: CGColor(gray: 0, alpha: 0.32))
        ctx.addPath(body)
        ctx.setFillColor(bgBottom)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.translateBy(x: 100, y: 100)
        ctx.scaleBy(x: 824 / 1024, y: 824 / 1024)
        let d = Detail(px: s * 824 / 1024)
        drawBackground(ctx)
        drawRings(ctx, d)
        drawSweep(ctx, d)
        drawDots(ctx, d)
    }
}

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("yazılamadı: \(url.path)") }
}

func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("\(tool) başarısız: \(p.terminationStatus)") }
}

let fm = FileManager.default

// 1) AppIcon.icns
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    writePNG(classicIcon(pt), iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    writePNG(classicIcon(pt * 2), iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
try! fm.removeItem(at: iconset)

// 2) AppIcon.icon: arka plan çizilmez, sistemin dolgusu (klasikle aynı renklerde degrade) kullanılır;
// katmanlar Liquid Glass ile işlenir. Renkli noktalar ayrı grupta, saydamlık rengi soldurmasın diye.
let iconDir = resources.appendingPathComponent("AppIcon.icon")
try? fm.removeItem(at: iconDir)
try! fm.createDirectory(at: iconDir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
let full = Detail(px: 1)
let layers: [String: (CGContext) -> Void] = [
    "dots": { drawDots($0, full) }, "sweep": { drawSweep($0, full) }, "rings": { drawRings($0, full) },
]
for (name, draw) in layers {
    writePNG(render(1024, draw), iconDir.appendingPathComponent("Assets/\(name).png"))
}
func iconColor(_ c: CGColor) -> String { "srgb:" + c.components!.map { String(format: "%.5f", $0) }.joined(separator: ",") }
// İnce halkalarda sistemin parlama (specular) efekti çizgide küçük koyu çentikler bırakıyor; radar grubunda kapalı.
func group(_ names: [String], translucency: Double, specular: Bool) -> [String: Any] {
    ["layers": names.map { ["name": $0, "image-name": "\($0).png"] },
     "shadow": ["kind": "neutral", "opacity": 0.5],
     "specular": specular,
     "translucency": ["enabled": translucency > 0, "value": translucency]]
}
let json: [String: Any] = [
    "fill": ["linear-gradient": [iconColor(bgTop), iconColor(bgBottom)]],
    "groups": [group(["dots"], translucency: 0, specular: true),
               group(["sweep", "rings"], translucency: 0.4, specular: false)],
    "supported-platforms": ["squares": ["macOS"]],
]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconDir.appendingPathComponent("icon.json"))

// 3) İsteğe bağlı önizlemeler
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for s in [1024, 128, 32, 16] { writePNG(classicIcon(s), dir.appendingPathComponent("icon-\(s).png")) }
    // Açık ve koyu zeminde gerçek piksel boyutlarında yan yana.
    let sizes = [256, 128, 64, 32, 16], gap = 40, rowH = 256 + 2 * gap
    let width = sizes.reduce(gap) { $0 + $1 + gap }
    let sheet = CGContext(data: nil, width: width, height: rowH * 2, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, bg) in [(1, rgb(0xF5F5F7)), (0, rgb(0x1E1E1E))] {
        sheet.setFillColor(bg)
        sheet.fill(CGRect(x: 0, y: row * rowH, width: width, height: rowH))
        var x = gap
        for s in sizes {
            sheet.draw(classicIcon(s), in: CGRect(x: x, y: row * rowH + (rowH - s) / 2, width: s, height: s))
            x += s + gap
        }
    }
    writePNG(sheet.makeImage()!, dir.appendingPathComponent("icon-preview.png"))
}
print("Yazıldı: Resources/AppIcon.icns, Resources/AppIcon.icon")
