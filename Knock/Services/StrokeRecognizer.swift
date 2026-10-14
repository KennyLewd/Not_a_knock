import Foundation

struct StrokePoint: Equatable {
    var x: Double
    var y: Double
}

/// Single-stroke glyphs only. A stroke ends when the finger lifts, so letters that
/// people draw with more than one stroke — A, H, T, E — are not reachable and are
/// deliberately absent rather than approximated.
enum StrokeGlyph: String, CaseIterable, Identifiable, Codable {
    case s, c, o, z, l

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var letter: Character { Character(rawValue.uppercased()) }

    var drawingHint: String {
        switch self {
        case .s: "Draw an S, starting at the top right"
        case .c: "Draw a C, starting at the top right"
        case .o: "Draw a full circle, starting at the top right"
        case .z: "Draw a Z: across, diagonally down, across"
        case .l: "Draw an L: straight down, then right"
        }
    }
}

/// Template matcher in the style of the $1 unistroke recognizer: resample to a fixed
/// number of equidistant points, normalize position and scale, then compare against
/// analytic templates. Rotation is deliberately *not* normalized — for letters it
/// would make a shape match its own rotations, and C rotated is not a C.
struct StrokeRecognizer {
    static let sampleCount = 48
    /// Beyond this mean normalized point distance a stroke is treated as no glyph.
    /// Without a rejection bound every stray drag would match its nearest letter.
    static let rejectionDistance = 0.25
    /// A stroke shorter than this fraction of the trackpad is treated as a tap or
    /// twitch rather than a drawing attempt.
    static let minimumPathLength = 0.35
    /// Path length divided by end-to-end span. A straight drag sits at 1.0; the
    /// least-curved glyph here is L at about 1.41. Template distance alone accepted
    /// a plain diagonal drag as an L, because shape matching never asked whether the
    /// stroke turned at all.
    static let minimumTurn = 1.2

    private let templates: [(glyph: StrokeGlyph, points: [StrokePoint])]

    init() {
        templates = StrokeGlyph.allCases.compactMap { glyph in
            let normalized = Self.normalize(Self.template(for: glyph))
            return normalized.isEmpty ? nil : (glyph, normalized)
        }
    }

    /// Returns the closest glyph, or nil when the stroke is too short, too sparse, or
    /// too unlike every template.
    func recognize(_ stroke: [StrokePoint]) -> StrokeGlyph? {
        guard stroke.count >= 8, let first = stroke.first, let last = stroke.last else { return nil }
        let length = Self.pathLength(stroke)
        guard length >= Self.minimumPathLength else { return nil }
        // A closed shape such as O has almost no span, so treat that as fully turned.
        let span = hypot(last.x - first.x, last.y - first.y)
        guard span <= 0.001 || length / span >= Self.minimumTurn else { return nil }
        let candidate = Self.normalize(stroke)
        guard !candidate.isEmpty else { return nil }
        var best: (glyph: StrokeGlyph, distance: Double)?
        for template in templates {
            let distance = Self.distance(candidate, template.points)
            if best == nil || distance < best!.distance { best = (template.glyph, distance) }
        }
        guard let best, best.distance <= Self.rejectionDistance else { return nil }
        return best.glyph
    }

    /// Exposed so tests and diagnostics can inspect margins rather than only the
    /// winning glyph, which is what makes a confusion threshold tunable.
    func distances(_ stroke: [StrokePoint]) -> [StrokeGlyph: Double] {
        let candidate = Self.normalize(stroke)
        guard !candidate.isEmpty else { return [:] }
        return Dictionary(uniqueKeysWithValues: templates.map { ($0.glyph, Self.distance(candidate, $0.points)) })
    }

    // MARK: - Geometry

    static func pathLength(_ points: [StrokePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private static func distance(_ a: [StrokePoint], _ b: [StrokePoint]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        let total = zip(a, b).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        return total / Double(a.count)
    }

    static func normalize(_ points: [StrokePoint]) -> [StrokePoint] {
        let sampled = resample(points, to: sampleCount)
        guard sampled.count == sampleCount else { return [] }
        let xs = sampled.map(\.x), ys = sampled.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }
        let scale = max(maxX - minX, maxY - minY)
        guard scale > 0, scale.isFinite else { return [] }
        let centreX = xs.reduce(0, +) / Double(sampled.count)
        let centreY = ys.reduce(0, +) / Double(sampled.count)
        return sampled.map { StrokePoint(x: ($0.x - centreX) / scale, y: ($0.y - centreY) / scale) }
    }

    private static func resample(_ points: [StrokePoint], to count: Int) -> [StrokePoint] {
        guard count > 1, points.count > 1 else { return [] }
        let total = pathLength(points)
        guard total > 0, total.isFinite else { return [] }
        let step = total / Double(count - 1)
        var result = [points[0]]
        var previous = points[0]
        var accumulated = 0.0
        var index = 1
        while index < points.count && result.count < count {
            let current = points[index]
            let segment = hypot(current.x - previous.x, current.y - previous.y)
            if segment <= 0 {
                index += 1
                continue
            }
            if accumulated + segment >= step {
                let ratio = (step - accumulated) / segment
                previous = StrokePoint(x: previous.x + ratio * (current.x - previous.x),
                                       y: previous.y + ratio * (current.y - previous.y))
                result.append(previous)
                accumulated = 0
            } else {
                accumulated += segment
                previous = current
                index += 1
            }
        }
        while result.count < count, let last = result.last { result.append(last) }
        return result
    }

    // MARK: - Templates

    /// Coordinates use x to the right and y downward, matching pointer deltas.
    static func template(for glyph: StrokeGlyph) -> [StrokePoint] {
        switch glyph {
        case .l:
            return polyline([StrokePoint(x: 0, y: 0), StrokePoint(x: 0, y: 1), StrokePoint(x: 1, y: 1)])
        case .z:
            return polyline([StrokePoint(x: 0, y: 0), StrokePoint(x: 1, y: 0),
                             StrokePoint(x: 0, y: 1), StrokePoint(x: 1, y: 1)])
        case .c:
            return arc(centre: StrokePoint(x: 0.5, y: 0.5), radius: 0.5, from: 315, to: 45)
        case .o:
            return arc(centre: StrokePoint(x: 0.5, y: 0.5), radius: 0.5, from: 315, to: -45)
        case .s:
            return arc(centre: StrokePoint(x: 0.5, y: 0.25), radius: 0.25, from: 315, to: 90)
                + arc(centre: StrokePoint(x: 0.5, y: 0.75), radius: 0.25, from: 270, to: 540)
        }
    }

    private static func polyline(_ corners: [StrokePoint], perSegment: Int = 24) -> [StrokePoint] {
        guard corners.count > 1 else { return corners }
        var result = [corners[0]]
        for (start, end) in zip(corners, corners.dropFirst()) {
            for step in 1...perSegment {
                let ratio = Double(step) / Double(perSegment)
                result.append(StrokePoint(x: start.x + ratio * (end.x - start.x),
                                          y: start.y + ratio * (end.y - start.y)))
            }
        }
        return result
    }

    private static func arc(centre: StrokePoint, radius: Double,
                            from startDegrees: Double, to endDegrees: Double,
                            steps: Int = 64) -> [StrokePoint] {
        (0...steps).map { step in
            let degrees = startDegrees + (endDegrees - startDegrees) * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            return StrokePoint(x: centre.x + radius * cos(radians),
                               y: centre.y + radius * sin(radians))
        }
    }
}
