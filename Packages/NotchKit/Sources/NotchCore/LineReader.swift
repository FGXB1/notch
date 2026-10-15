import Foundation

/// Splits a child process's stdout into lines. Called from the pipe's background queue only, one chunk at
/// a time, so the unchecked buffer is never touched concurrently.
public final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: @Sendable (Data) -> Void

    public init(onLine: @escaping @Sendable (Data) -> Void) {
        self.onLine = onLine
    }

    public func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty {
                onLine(Data(line))
            }
        }
    }
}
