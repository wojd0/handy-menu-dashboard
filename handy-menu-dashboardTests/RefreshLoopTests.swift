import Foundation
import Testing
@testable import handy_menu_dashboard

@Suite("Refresh loop")
struct RefreshLoopTests {
    @Test func startRunsTheTickRepeatedly() async {
        let loop = RefreshLoop(interval: .milliseconds(1))
        var ticks = 0

        loop.start { ticks += 1 }
        let reachedThree = await waitUntil { ticks >= 3 }

        #expect(reachedThree)
        loop.stop()
    }

    @Test func stopHaltsTheTick() async {
        let loop = RefreshLoop(interval: .milliseconds(1))
        var ticks = 0
        loop.start { ticks += 1 }
        let started = await waitUntil { ticks >= 2 }

        loop.stop()
        let afterStop = ticks
        await settle()

        #expect(started)
        #expect(ticks == afterStop)
    }

    @Test func releasingTheLoopCancelsTheTick() async {
        var loop: RefreshLoop? = RefreshLoop(interval: .milliseconds(1))
        var ticks = 0
        loop?.start { ticks += 1 }
        let started = await waitUntil { ticks >= 2 }

        loop = nil
        await settle()
        let afterRelease = ticks
        await settle()

        #expect(started)
        #expect(ticks == afterRelease)
    }

    @Test func startReplacesAPreviousTick() async {
        let loop = RefreshLoop(interval: .milliseconds(1))
        var first = 0
        var second = 0
        loop.start { first += 1 }
        let firstStarted = await waitUntil { first >= 2 }

        loop.start { second += 1 }
        let secondStarted = await waitUntil { second >= 2 }
        let firstAfterReplace = first
        await settle()

        #expect(firstStarted)
        #expect(secondStarted)
        #expect(first == firstAfterReplace)
        loop.stop()
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }
}
