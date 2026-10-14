import XCTest
@testable import KnockCore

final class StrokeRecognizerTests: XCTestCase {
    private let recognizer = StrokeRecognizer()

    /// Redraws a template the way a hand would: uneven speed, so samples bunch up in
    /// places, plus jitter. A recognizer that only passes on its own templates has
    /// proved nothing.
    private func handDrawn(_ glyph: StrokeGlyph, jitter: Double, seed: UInt64) -> [StrokePoint] {
        var state = seed | 1
        func noise() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return (Double(state % 2000) / 1000 - 1) * jitter
        }
        let source = StrokeRecognizer.template(for: glyph)
        var result: [StrokePoint] = []
        var index = 0.0
        while Int(index) < source.count {
            let point = source[Int(index)]
            result.append(StrokePoint(x: point.x + noise(), y: point.y + noise()))
            // Uneven sampling: sometimes creep, sometimes skip ahead.
            index += 1 + Double(state % 3)
        }
        if let last = source.last { result.append(last) }
        return result
    }

    func testEveryGlyphMatchesItsOwnTemplate() {
        for glyph in StrokeGlyph.allCases {
            let stroke = StrokeRecognizer.template(for: glyph)
            XCTAssertEqual(recognizer.recognize(stroke), glyph, "\(glyph) failed on its own template")
        }
    }

    func testHandDrawnStrokesAreRecognizedAcrossSeeds() {
        for glyph in StrokeGlyph.allCases {
            for seed in [7 as UInt64, 99, 4242] {
                let stroke = handDrawn(glyph, jitter: 0.04, seed: seed)
                XCTAssertEqual(recognizer.recognize(stroke), glyph,
                               "\(glyph) failed with seed \(seed)")
            }
        }
    }

    /// The confusable pairs are C against O, which differ only in how far the arc
    /// closes, and S against Z, which trace similar corners.
    func testConfusablePairsStaySeparated() {
        for glyph in StrokeGlyph.allCases {
            let distances = recognizer.distances(handDrawn(glyph, jitter: 0.03, seed: 31))
            let own = distances[glyph] ?? .infinity
            let others = distances.filter { $0.key != glyph }.values
            let closestOther = others.min() ?? .infinity
            XCTAssertLessThan(own, closestOther, "\(glyph) is closer to another glyph than itself")
            XCTAssertLessThan(own, closestOther * 0.75,
                              "\(glyph) has too little margin: own \(own), nearest other \(closestOther)")
        }
    }

    func testOrdinaryDragsAndTwitchesAreRejected() {
        let straightDrag = (0...40).map { StrokePoint(x: Double($0) / 40, y: Double($0) / 80) }
        XCTAssertNil(recognizer.recognize(straightDrag), "A plain diagonal drag must not be a glyph")

        let horizontal = (0...40).map { StrokePoint(x: Double($0) / 40, y: 0) }
        XCTAssertNil(recognizer.recognize(horizontal), "A flick must not be a glyph")

        let twitch = (0...20).map { StrokePoint(x: Double($0) * 0.002, y: Double($0) * 0.002) }
        XCTAssertNil(recognizer.recognize(twitch), "A short twitch is below the length floor")

        XCTAssertNil(recognizer.recognize([]))
        XCTAssertNil(recognizer.recognize([StrokePoint(x: 0, y: 0), StrokePoint(x: 1, y: 1)]))
    }

    /// Guards the turn rule itself: every glyph must clear the threshold with margin,
    /// otherwise tightening it to reject drags would start rejecting real strokes.
    func testEveryGlyphTurnsWellPastTheStraightLineFloor() {
        for glyph in StrokeGlyph.allCases {
            let stroke = StrokeRecognizer.template(for: glyph)
            let length = StrokeRecognizer.pathLength(stroke)
            let span = hypot(stroke.last!.x - stroke.first!.x, stroke.last!.y - stroke.first!.y)
            let ratio = span <= 0.001 ? Double.infinity : length / span
            XCTAssertGreaterThan(ratio, StrokeRecognizer.minimumTurn * 1.1,
                                 "\(glyph) has only \(ratio) turn ratio")
        }
    }

    func testScaleAndPositionDoNotMatter() {
        for glyph in StrokeGlyph.allCases {
            let shifted = StrokeRecognizer.template(for: glyph).map {
                StrokePoint(x: $0.x * 3.5 - 40, y: $0.y * 3.5 + 220)
            }
            XCTAssertEqual(recognizer.recognize(shifted), glyph,
                           "\(glyph) should be scale and position invariant")
        }
    }

    func testReversedStrokeIsNotSilentlyAccepted() {
        // Direction is meaningful: an L drawn bottom-up is not an L.
        let reversed = Array(StrokeRecognizer.template(for: .l).reversed())
        XCTAssertNotEqual(recognizer.recognize(reversed), StrokeGlyph.l)
    }
}
