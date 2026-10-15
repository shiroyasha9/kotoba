import Testing

@testable import KotobaCore

/// A 1512 x 845 visible frame with a 70 pt Dock below it and the menu bar above it.
struct IndicatorPlacementTests {
    static let visible = ScreenRect(x: 0, y: 70, width: 1512, height: 845)

    struct FrameRow: Sendable, CustomTestStringConvertible {
        let anchor: IndicatorAnchor
        let isCompact: Bool
        let frame: ScreenRect

        var testDescription: String { "\(anchor), compact: \(isCompact)" }
    }

    static let frameRows: [FrameRow] = [
        FrameRow(anchor: .bottomCenter, isCompact: true, frame: ScreenRect(x: 636, y: 94, width: 240, height: 40)),
        FrameRow(anchor: .bottomCenter, isCompact: false, frame: ScreenRect(x: 636, y: 94, width: 240, height: 40)),
        FrameRow(anchor: .left, isCompact: true, frame: ScreenRect(x: 12, y: 436.5, width: 40, height: 112)),
        FrameRow(anchor: .left, isCompact: false, frame: ScreenRect(x: 12, y: 472.5, width: 240, height: 40)),
        FrameRow(anchor: .right, isCompact: true, frame: ScreenRect(x: 1460, y: 436.5, width: 40, height: 112)),
        FrameRow(anchor: .right, isCompact: false, frame: ScreenRect(x: 1260, y: 472.5, width: 240, height: 40)),
    ]

    @Test(arguments: frameRows)
    func theFrameSitsAtItsAnchorInsideTheVisibleFrame(_ row: FrameRow) {
        let frame = IndicatorPlacement.frame(
            at: row.anchor, isCompact: row.isCompact, contentWidth: 240, in: Self.visible)
        #expect(frame == row.frame)
        #expect(frame.minX >= Self.visible.minX && frame.maxX <= Self.visible.maxX)
        #expect(frame.minY >= Self.visible.minY && frame.maxY <= Self.visible.maxY)
    }

    static let roundRows: [(IndicatorAnchor, ScreenRect)] = [
        (.bottomCenter, ScreenRect(x: 736, y: 94, width: 40, height: 40)),
        (.left, ScreenRect(x: 12, y: 472.5, width: 40, height: 40)),
        (.right, ScreenRect(x: 1460, y: 472.5, width: 40, height: 40)),
    ]

    @Test(arguments: roundRows)
    func theRoundIdlePillSitsWhereThePillWithTextCenters(_ anchor: IndicatorAnchor, _ frame: ScreenRect) {
        let round = IndicatorPlacement.roundFrame(at: anchor, in: Self.visible)
        #expect(round == frame)
        let pill = IndicatorPlacement.frame(at: anchor, isCompact: true, contentWidth: 240, in: Self.visible)
        #expect(round.mid.y == pill.mid.y)
        #expect(anchor != .bottomCenter || round.mid.x == pill.mid.x)
    }

    @Test func theFrameFollowsAVisibleFrameOnASecondScreen() {
        let secondScreen = ScreenRect(x: 1512, y: -200, width: 1920, height: 1055)
        let frame = IndicatorPlacement.frame(at: .right, isCompact: true, contentWidth: 240, in: secondScreen)
        #expect(frame == ScreenRect(x: 3380, y: 271.5, width: 40, height: 112))
    }

    @Test func aHorizontalPillFitsItsContentWithinLimits() {
        func width(_ contentWidth: Double, at anchor: IndicatorAnchor = .bottomCenter) -> Double {
            IndicatorPlacement.frame(at: anchor, isCompact: false, contentWidth: contentWidth, in: Self.visible).width
        }
        #expect(width(172) == 172)
        #expect(width(60) == 120)
        #expect(width(900) == 360)
        #expect(width(172, at: .right) == 172)
        let vertical = IndicatorPlacement.frame(at: .left, isCompact: true, contentWidth: 172, in: Self.visible)
        #expect(vertical.width == 40)
    }

    @Test func theDraggedPillIsASmallCircleUnderThePointer() {
        let frame = IndicatorPlacement.dragFrame(centeredAt: ScreenPoint(x: 300, y: 200))
        #expect(frame == ScreenRect(x: 280, y: 180, width: 40, height: 40))
    }

    struct DropRow: Sendable, CustomTestStringConvertible {
        let name: String
        let point: ScreenPoint
        let anchor: IndicatorAnchor

        var testDescription: String { name }
    }

    static let dropRows: [DropRow] = [
        DropRow(name: "near the bottom center", point: ScreenPoint(x: 700, y: 140), anchor: .bottomCenter),
        DropRow(name: "near the left edge", point: ScreenPoint(x: 30, y: 400), anchor: .left),
        DropRow(name: "near the right edge", point: ScreenPoint(x: 1490, y: 700), anchor: .right),
        DropRow(name: "low and left, closer to the bottom", point: ScreenPoint(x: 500, y: 80), anchor: .bottomCenter),
        DropRow(name: "low and left, closer to the edge", point: ScreenPoint(x: 40, y: 200), anchor: .left),
        DropRow(name: "the top middle", point: ScreenPoint(x: 756, y: 900), anchor: .bottomCenter),
        DropRow(name: "outside the screen to the right", point: ScreenPoint(x: 1700, y: 500), anchor: .right),
    ]

    @Test(arguments: dropRows)
    func aDropSnapsToTheNearestAnchor(_ row: DropRow) {
        #expect(IndicatorPlacement.nearestAnchor(to: row.point, in: Self.visible) == row.anchor)
    }

    @Test func aSmallMoveIsAClickAndALargerOneIsADrag() {
        let start = ScreenPoint(x: 100, y: 100)
        #expect(!IndicatorPlacement.isDrag(from: start, to: ScreenPoint(x: 102, y: 102)))
        #expect(IndicatorPlacement.isDrag(from: start, to: ScreenPoint(x: 104, y: 100)))
        #expect(IndicatorPlacement.isDrag(from: start, to: ScreenPoint(x: 97, y: 96)))
    }

    @Test func theScreenHoldingMostOfTheWindowWins() {
        let screens = [
            ScreenRect(x: 0, y: 0, width: 1512, height: 982),
            ScreenRect(x: 1512, y: 0, width: 1920, height: 1080),
        ]
        let mostlyOnSecond = ScreenRect(x: 1400, y: 100, width: 800, height: 600)
        #expect(IndicatorPlacement.screenIndex(holding: mostlyOnSecond, among: screens) == 1)
        let onFirst = ScreenRect(x: 100, y: 100, width: 800, height: 600)
        #expect(IndicatorPlacement.screenIndex(holding: onFirst, among: screens) == 0)
        let offScreen = ScreenRect(x: 5000, y: 0, width: 100, height: 100)
        #expect(IndicatorPlacement.screenIndex(holding: offScreen, among: screens) == nil)
    }

    @Test func aWindowServerRectFlipsToScreenCoordinates() {
        // A 400 x 300 window 50 pt below the top of a 982 pt tall primary screen.
        let windowServer = ScreenRect(x: 10, y: 50, width: 400, height: 300)
        let rect = IndicatorPlacement.screenRect(fromWindowServer: windowServer, primaryScreenHeight: 982)
        #expect(rect == ScreenRect(x: 10, y: 632, width: 400, height: 300))
    }

    @Test func theAnchorRoundTripsThroughItsSavedValue() {
        for anchor in IndicatorAnchor.allCases {
            #expect(IndicatorAnchor(rawValue: anchor.rawValue) == anchor)
        }
    }
}
