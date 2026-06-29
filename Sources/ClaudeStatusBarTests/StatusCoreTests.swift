import StatusCore
import TestSupport

private func event(_ name: String, notification: String? = nil) -> HookEvent {
    HookEvent(sessionId: "s1", hookEventName: name, notificationType: notification, cwd: "/tmp/proj")
}

func stateMapperTests() -> TestSuite { ("StateMapperTests", { t in
    t.expectEqual(StateMapper.outcome(for: event("Notification", notification: "permission_prompt")), .set(.red))
    t.expectEqual(StateMapper.outcome(for: event("Notification", notification: "idle_prompt")), .set(.red))
    t.expectEqual(StateMapper.outcome(for: event("Notification", notification: "auth_success")), .ignore)
    t.expectEqual(StateMapper.outcome(for: event("Notification", notification: "elicitation_dialog")), .ignore)
    t.expectEqual(StateMapper.outcome(for: event("Notification", notification: nil)), .ignore)
    t.expectEqual(StateMapper.outcome(for: event("UserPromptSubmit")), .set(.yellow))
    t.expectEqual(StateMapper.outcome(for: event("PreToolUse")), .set(.yellow))
    t.expectEqual(StateMapper.outcome(for: event("PostToolUse")), .set(.yellow))
    t.expectEqual(StateMapper.outcome(for: event("PreCompact")), .set(.yellow))
    t.expectEqual(StateMapper.outcome(for: event("PostCompact")), .set(.yellow))
    t.expectEqual(StateMapper.outcome(for: event("Stop")), .set(.green))
    t.expectEqual(StateMapper.outcome(for: event("SessionStart")), .create)
    t.expectEqual(StateMapper.outcome(for: event("SessionEnd")), .remove)
    t.expectEqual(StateMapper.outcome(for: event("SomethingWeird")), .ignore)

    // subagent context (agent_id present): a subagent finishing must NOT mark the
    // session done/removed; tool use still counts as busy.
    func sub(_ name: String) -> HookEvent {
        HookEvent(sessionId: "s1", hookEventName: name, cwd: "/tmp/proj", agentId: "agent-1")
    }
    t.expectEqual(StateMapper.outcome(for: sub("Stop")), .ignore)
    t.expectEqual(StateMapper.outcome(for: sub("SessionEnd")), .ignore)
    t.expectEqual(StateMapper.outcome(for: sub("SessionStart")), .ignore)
    t.expectEqual(StateMapper.outcome(for: sub("PreToolUse")), .set(.yellow))
}) }

func aggregationTests() -> TestSuite { ("AggregationTests", { t in
    t.expectEqual(SessionState.aggregate([.yellow, .red, .green]), .red)
    t.expectEqual(SessionState.aggregate([.green, .yellow, .green]), .yellow)
    t.expectEqual(SessionState.aggregate([.green, .green]), .green)
    t.expectEqual(SessionState.aggregate([]), .green)
    t.expectEqual(SessionState.aggregate([.yellow, .yellow, .red]), .red)
}) }
