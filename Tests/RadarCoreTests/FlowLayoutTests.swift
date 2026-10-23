import Testing
import Foundation
import CoreGraphics
@testable import RadarCore

private func t(_ id: Int, _ state: String, _ req: [Int], from: Int? = nil) -> Topic {
    Topic(id: id, title: "t\(id)", state: state, summary: "", requests: req, from: from)
}

@Test func flowLayoutMainLineAndBranches() {
    let r = flowLayout([t(1, "done", [1]), t(2, "open", [2], from: 1), t(3, "done", [3], from: 1), t(4, "active", [4])])
    #expect(r == [FlowNode(topicId: 1, column: 0, lane: 0, parent: nil), FlowNode(topicId: 2, column: 1, lane: -1, parent: 1),
                  FlowNode(topicId: 3, column: 2, lane: 0, parent: nil), FlowNode(topicId: 4, column: 3, lane: 0, parent: nil)])
}
@Test func flowLayoutAlternatesSides() {
    let r = flowLayout([t(1, "done", [1]), t(2, "open", [2], from: 1), t(3, "open", [3], from: 1)])
    #expect(r.map(\.lane) == [0, -1, 1])
}
@Test func flowLayoutNestsOnSameSide() {
    let r = flowLayout([t(1, "done", [1]), t(2, "open", [2], from: 1), t(3, "open", [3], from: 2)])
    #expect(r.map(\.lane) == [0, -1, -2])
    #expect(r[2].parent == 2)
}
@Test func flowLayoutIgnoresInvalidFrom() {
    let r = flowLayout([t(1, "open", [1], from: 99), t(2, "open", [2], from: 2), t(3, "open", [3], from: 4), t(4, "open", [4])])
    #expect(r.allSatisfy { $0.lane == 0 && $0.parent == nil })
}
@Test func flowLayoutSortsByFirstRequest() {
    let r = flowLayout([t(3, "open", [5]), t(1, "done", [1]), t(2, "done", [2])])
    #expect(r.map(\.topicId) == [1, 2, 3])
    #expect(r.map(\.column) == [0, 1, 2])
}
@Test func flowLayoutEmpty() { #expect(flowLayout([]) == []) }

@Test func clampCameraKeepsCenterInsideContent() {
    let c = clampCamera(Camera(x: 5000, y: -3000, scale: 1), content: CGRect(x: 0, y: 0, width: 1000, height: 200), viewport: CGSize(width: 800, height: 600))
    #expect(c.x == 400); #expect(c.y == 100)
}
@Test func clampCameraClampsScale() {
    let content = CGRect(x: 0, y: 0, width: 1000, height: 200), vp = CGSize(width: 800, height: 600)
    #expect(clampCamera(Camera(x: 0, y: 0, scale: 5), content: content, viewport: vp).scale == 2.0)
    #expect(clampCamera(Camera(x: 0, y: 0, scale: 0.1), content: content, viewport: vp).scale == 0.4)
}
@Test func fitCameraClampsMinScale() {
    let vp = CGSize(width: 800, height: 600)
    #expect(fitCamera(content: CGRect(x: 0, y: 0, width: 4000, height: 200), viewport: vp).scale == 0.4)
    #expect(fitCamera(content: CGRect(x: 0, y: 0, width: 100, height: 50), viewport: vp).scale == 1)
}
@Test func focusCameraCentersRect() {
    let c = focusCamera(on: CGRect(x: 500, y: 100, width: 200, height: 60), scale: 1, viewport: CGSize(width: 800, height: 600))
    #expect(c.x == -200); #expect(c.y == 170)
}
@Test func resolveSelectionFallsBackToActive() {
    let ts = [t(1, "done", [1]), t(2, "active", [2]), t(3, "open", [3])]
    #expect(resolveTopicSelection(3, topics: ts) == 3)
    #expect(resolveTopicSelection(7, topics: ts) == 2)
    #expect(resolveTopicSelection(7, topics: [t(1, "done", [1]), t(3, "open", [3])]) == 3)
    #expect(resolveTopicSelection(7, topics: []) == nil)
}
