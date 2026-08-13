import Foundation
import Combine

final class FileWatcher: ObservableObject {
    @Published var fileDidChange = false

    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var fileURL: URL?

    init(fileURL: URL? = nil) {
        if let url = fileURL {
            startWatching(url: url)
        }
    }

    deinit {
        stopWatching()
    }

    func startWatching(url: URL) {
        stopWatching()
        self.fileURL = url

        guard url.isFileURL else { return }

        // Start accessing security-scoped resource if required
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.debounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.fileDidChange = true
                }
            }
            self.debounceWorkItem = workItem
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25, execute: workItem)
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
        fileURL = nil
    }

    func resetChangeFlag() {
        fileDidChange = false
    }
}
