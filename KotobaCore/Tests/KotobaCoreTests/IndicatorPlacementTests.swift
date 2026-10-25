import Testing

@testable import KotobaCore

/// A 1512 x 845 visible frame with a 70 pt Dock below it and the menu bar above it.
struct IndicatorPlacementTests {
    static let visible = ScreenRect(x: 0, y: 70, width: 1512, height: 845)

    /// The capsule's thickness: a 24.5 pt button and 6 pt above and below it.
    static let thickness = 36.5

    static let roomRows: [(IndicatorAnchor, ScreenRect)] = [
        (.bottomCenter, ScreenRect(x: 576, y: 94, width: 360, height: 36.5)),
        (.left, ScreenRect(x: 12, y: 312.5, width: 360, height: 360)),
        (.right, ScreenRect(x: 1140, y: 312.5, width: 360, height: 360)),
    ]

    @Test(arguments: roomRows)
    func theRoomSitsAtItsAnchorInsideTheVisibleFrame(_ anchor: IndicatorAnchor, _ room: ScreenRect) {
        let frame = IndicatorPlacement.room(at: anchor, thickness: Self.thickness, in: Self.visible)
        #expect(frame == room)
        #expect(frame.minX >= Self.visible.minX && frame.maxX <= Self.visible.maxX)
        #expect(frame.minY >= Self.visible.minY && frame.maxY <= Self.visible.maxY)
    }

    @Test func theRoomFollowsAVisibleFrameOnASecondScreen() {
        let secondScreen = ScreenRect(x: 1512, y: -200, width: 1920, height: 1055)
        let room = IndicatorPlacement.room(at: .right, thickness: Self.thickness, in: secondScreen)
        #expect(room == ScreenRect(x: 3060, y: 147.5, width: 360, height: 360))
    }

    private static func capsule(_ width: Double, _ height: Double, at anchor: IndicatorAnchor) -> ScreenRect {
        IndicatorPlacement.capsule(
            width: width, height: height, at: anchor, thickness: thickness,
            in: IndicatorPlacement.room(at: anchor, thickness: thickness, in: visible))
    }

    /// At the bottom every shape grows from the room's middle.
    @Test func atTheBottomEveryCapsuleSharesTheCentre() {
        #expect(Self.capsule(40, 8, at: .bottomCenter) == ScreenRect(x: 736, y: 108.25, width: 40, height: 8))
        #expect(Self.capsule(172, 36.5, at: .bottomCenter) == ScreenRect(x: 670, y: 94, width: 172, height: 36.5))
    }

    /// At a side edge a capsule touches the edge and reaches inward; the idle bar centres on the axis of a full one.
    @Test func atASideEdgeACapsuleTouchesTheEdge() {
        #expect(Self.capsule(36.5, 120, at: .left) == ScreenRect(x: 12, y: 432.5, width: 36.5, height: 120))
        #expect(Self.capsule(300, 36.5, at: .left) == ScreenRect(x: 12, y: 474.25, width: 300, height: 36.5))
        #expect(Self.capsule(8, 40, at: .left) == ScreenRect(x: 26.25, y: 472.5, width: 8, height: 40))
        #expect(Self.capsule(36.5, 120, at: .right) == ScreenRect(x: 1463.5, y: 432.5, width: 36.5, height: 120))
        #expect(Self.capsule(300, 36.5, at: .right) == ScreenRect(x: 1200, y: 474.25, width: 300, height: 36.5))
        #expect(Self.capsule(8, 40, at: .right) == ScreenRect(x: 1477.75, y: 472.5, width: 8, height: 40))
    }

    @Test func onlyAPillWithoutWordsStandsVerticalAndOnlyAtASideEdge() {
        #expect(IndicatorPlacement.isVertical(at: .left, hasWords: false))
        #expect(IndicatorPlacement.isVertical(at: .right, hasWords: false))
        #expect(!IndicatorPlacement.isVertical(at: .bottomCenter, hasWords: false))
        #expect(!IndicatorPlacement.isVertical(at: .left, hasWords: true))
        #expect(!IndicatorPlacement.isVertical(at: .right, hasWords: true))
    }

    @Test func theDraggedPillKeepsItsRoomAndMovesWithThePointer() {
        let room = ScreenRect(x: 576, y: 104, width: 360, height: 36)
        let dragged = IndicatorPlacement.draggedRoom(
            room, from: ScreenPoint(x: 760, y: 120), to: ScreenPoint(x: 700, y: 400))
        #expect(dragged == ScreenRect(x: 516, y: 384, width: 360, height: 36))
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
        #expect(
            IndicatorPlacement.nearestAnchor(to: row.point, thickness: Self.thickness, in: Self.visible) == row.anchor)
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
