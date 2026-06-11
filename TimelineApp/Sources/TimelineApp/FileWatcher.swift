import Foundation

/// Watches a file for external changes (writes, atomic-save renames,
/// deletes) and fires a debounced callback on the main queue. Re-arms
/// itself after atomic saves replace the file.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var debounce: DispatchWorkItem?
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit {
        cancel()
    }

    private func arm() {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            // Atomic saves replace the file: drop the stale descriptor
            // and watch the new file at the same path
            if events.contains(.rename) || events.contains(.delete) {
                self.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.arm()
                    self.fire()
                }
            } else {
                self.fire()
            }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    private func fire() {
        debounce?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancel() {
        source?.cancel()
        source = nil
    }
}
