import Foundation

/// Kart satırı: metin ve en çok kaç satıra sığacağı (nil: sınırsız, tam sarılır)
public struct CardRowSpec: Equatable, Sendable {
    public var text: String
    public var maxLines: Int?
    public init(_ text: String, maxLines: Int? = nil) { self.text = text; self.maxLines = maxLines }
}

/// Kelime kelime sarılan metnin tahmini satır sayısı; boş metin de bir satır sayılır
public func wrappedLineCount(_ text: String, charsPerLine: Int) -> Int {
    let width = max(charsPerLine, 1)
    var lines = 1, used = 0
    for word in text.split(whereSeparator: \.isWhitespace) {
        var n = word.count
        if used > 0 && used + 1 + n <= width { used += 1 + n; continue }
        if used > 0 { lines += 1 }
        while n > width { lines += 1; n -= width }   // satırdan uzun kelime bölünür
        used = n
    }
    return lines
}

/// Kartın alt bölümündeki satırların tahmini yüksekliği: ayraç/boşluk 13 pt, her satır 4 pt aralık, her metin satırı 15 pt.
/// charsPerLine: .subheadline yazıyla satırın alabileceği yaklaşık karakter (kart eni - dolgu - 19 pt simge sütunu).
public func infoRowsHeight(_ rows: [CardRowSpec], charsPerLine: Int) -> Double {
    guard !rows.isEmpty else { return 0 }
    let lines = rows.reduce(0) { $0 + min(wrappedLineCount($1.text, charsPerLine: charsPerLine), $1.maxLines ?? .max) }
    return 13 + Double(rows.count) * 4 + Double(lines) * 15
}

/// Kart eninden satır başına yaklaşık karakter: metin eni = en - 24 (dolgu) - 19 (simge + aralık); .subheadline ortalama ~5.8 pt/karakter
public func charsPerLine(cardWidth: Double) -> Int { max(Int((cardWidth - 24 - 19) / 5.8), 1) }

/// "Kapat" düğme satırının tahmini yüksekliği: küçük bordered düğme 22 pt + üstte 6 pt aralık; bilgi satırı yoksa ayraç/boşluk 13 pt da eklenir
public func closeRowHeight(hasInfo: Bool) -> Double { (hasInfo ? 0 : 13) + 28 }
