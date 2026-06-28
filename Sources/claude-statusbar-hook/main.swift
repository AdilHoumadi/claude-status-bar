import Foundation
import StatusCore
import StatusStore

// Claude Code hook entry point. Reads the hook's stdin JSON and updates the session
// state file. ALWAYS exits 0 (fail-open) and runs synchronously: a status hook must
// never block or fail a Claude Code turn. Invoked by absolute path so it needs no PATH.
let data = FileHandle.standardInput.readDataToEndOfFile()
if let event = try? JSONDecoder().decode(HookEvent.self, from: data) {
    let store = StateStore(directory: StateStore.defaultDirectory())
    HookProcessor.apply(event, store: store, now: Date())
}
exit(0)
