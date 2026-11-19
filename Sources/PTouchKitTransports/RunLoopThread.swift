#if canImport(Darwin)
import Foundation

/// A thread with its own run loop. IOBluetooth and ExternalAccessory streams
/// deliver callbacks on the run loop they were scheduled on, which async code
/// doesn't provide.
final class RunLoopThread: Thread, @unchecked Sendable {
    static let shared: RunLoopThread = {
        let t = RunLoopThread()
        t.name = "PTouchKitTransports.RunLoop"
        t.start()
        t.ready.wait()
        return t
    }()

    private let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A port keeps the run loop running when no other source is attached.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    /// Runs `body` on this thread and waits for it.
    func run<T>(_ body: @escaping () throws -> T) throws -> T {
        if Thread.current === self { return try body() }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            result = Result { try body() }
            done.signal()
        }
        CFRunLoopWakeUp(runLoop)
        done.wait()
        return try result.get()
    }
}
#endif
