import Foundation

/// Calls `onChange` when entries in a directory are added, removed, or renamed — which is
/// every write to the state store, since `.atomic` writes land via a rename. Replaces
/// polling: the app sleeps until a hook actually writes, instead of waking twice a second.
///
/// Bursts (several hooks firing together) are coalesced into one callback after `latency`.
/// If the directory itself is deleted or moved, the watcher re-arms on the recreated path.
public final class DirectoryWatcher: @unchecked Sendable {
    private let directory: URL
    private let queue: DispatchQueue
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending = false   // guarded by `queue`

    public init(
        directory: URL,
        queue: DispatchQueue = .main,
        latency: TimeInterval = 0.1,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.directory = directory
        self.queue = queue
        self.latency = latency
        self.onChange = onChange
    }

    deinit { source?.cancel() }

    public func start() {
        queue.async { self.arm() }
    }

    public func stop() {
        queue.async {
            self.source?.cancel()
            self.source = nil
        }
    }

    private func arm() {
        source?.cancel()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let watch = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
        watch.setEventHandler { [weak self] in
            guard let self else { return }
            if !watch.data.isDisjoint(with: [.delete, .rename]) {
                self.arm()   // the directory went away: watch the recreated one
            }
            self.schedule()
        }
        watch.setCancelHandler { close(descriptor) }
        source = watch
        watch.resume()
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + latency) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.onChange()
        }
    }
}
