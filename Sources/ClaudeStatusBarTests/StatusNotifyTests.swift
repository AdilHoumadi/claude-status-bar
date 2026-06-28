import Foundation
import StatusApp
import StatusCore
import TestSupport

func notificationCoordinatorTests() -> TestSuite { ("NotificationCoordinatorTests", { t in
    func item(_ id: String, _ state: SessionState, cwd: String? = "/work/app") -> SessionViewItem {
        SessionViewItem(id: id, state: state, cwd: cwd, elapsed: 0)
    }
    func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    let settings = NotificationSettings()  // notify red+green, sound on, debounce 5

    let c = NotificationCoordinator()

    // first sighting records only — no launch burst
    var out = c.process(sessions: [item("s", .yellow)], settings: settings, now: at(0))
    t.expectEqual(out.count, 0)

    // yellow -> red fires "needs you"
    out = c.process(sessions: [item("s", .red)], settings: settings, now: at(1))
    t.expectEqual(out.count, 1)
    t.expectEqual(out.first?.kind, .needsYou)
    t.expectEqual(out.first?.sessionId, "s")

    // red -> yellow: yellow not a notify state -> nothing
    out = c.process(sessions: [item("s", .yellow)], settings: settings, now: at(2))
    t.expectEqual(out.count, 0)

    // yellow -> red again within debounce window (last red fired t=1, now t=3, interval 5) -> suppressed
    out = c.process(sessions: [item("s", .red)], settings: settings, now: at(3))
    t.expectEqual(out.count, 0)

    // past the debounce window red fires again
    _ = c.process(sessions: [item("s", .yellow)], settings: settings, now: at(10))
    out = c.process(sessions: [item("s", .red)], settings: settings, now: at(11))
    t.expectEqual(out.count, 1)
    t.expectEqual(out.first?.kind, .needsYou)

    // -> green fires "done"
    out = c.process(sessions: [item("s", .green)], settings: settings, now: at(20))
    t.expectEqual(out.count, 1)
    t.expectEqual(out.first?.kind, .done)

    // muted project: real transition still produces nothing
    let cm = NotificationCoordinator()
    let muted = NotificationSettings(mutedProjects: ["/work/app"])
    _ = cm.process(sessions: [item("m", .yellow)], settings: muted, now: at(0))
    out = cm.process(sessions: [item("m", .red)], settings: muted, now: at(1))
    t.expectEqual(out.count, 0)

    // notify on running (yellow) when enabled -> .started
    let cy = NotificationCoordinator()
    let allStates = NotificationSettings(notifyStates: [.red, .yellow, .green])
    _ = cy.process(sessions: [item("y", .green)], settings: allStates, now: at(0))
    out = cy.process(sessions: [item("y", .yellow)], settings: allStates, now: at(1))
    t.expectEqual(out.count, 1)
    t.expectEqual(out.first?.kind, .started)

    // disabled transition: notify only on red -> a ->green is silent, ->red fires
    let cd = NotificationCoordinator()
    let redOnly = NotificationSettings(notifyStates: [.red])
    _ = cd.process(sessions: [item("d", .yellow)], settings: redOnly, now: at(0))
    out = cd.process(sessions: [item("d", .green)], settings: redOnly, now: at(1))
    t.expectEqual(out.count, 0)
    out = cd.process(sessions: [item("d", .red)], settings: redOnly, now: at(2))
    t.expectEqual(out.count, 1)
}) }
