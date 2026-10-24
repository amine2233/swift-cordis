/// Single serial executor for the whole plugin graph.
/// Every mutation of the graph (provide, withdraw, start, stop) is serialized here,
/// which is what makes reactive restarts deterministic.
@globalActor
public actor CordisActor {
    public static let shared = CordisActor()
}

public typealias Disposer = @CordisActor () async -> Void

/// Idempotent teardown handle. Calling it twice is a no-op.
@CordisActor
public final class Disposable {
    private var action: Disposer?

    init(_ action: @escaping Disposer) {
        self.action = action
    }

    public var isDisposed: Bool {
        action == nil
    }

    public func callAsFunction() async {
        guard let action else { return }

        self.action = nil
        await action()
    }
}

/// The "time" half of spatiotemporal composability:
/// every side effect registered in a scope is undone when the scope dies,
/// in reverse order of registration (LIFO, like `defer`).
@CordisActor
public final class Scope {
    private var handles: [Int: Disposable] = [:]
    private var counter = 0
    public private(set) var isDisposed = false

    init() {}

    /// Registers a teardown. If the scope is already dead, the teardown runs immediately.
    @discardableResult
    public func collect(_ teardown: @escaping Disposer) -> Disposable {
        counter += 1
        let id = counter
        let handle = Disposable { [weak self] in
            self?.handles[id] = nil
            await teardown()
        }
        if isDisposed {
            Task { @CordisActor in await handle() }
        } else {
            handles[id] = handle
        }
        return handle
    }

    func dispose() async {
        guard !isDisposed else { return }

        isDisposed = true
        let ordered = handles.sorted { $0.key > $1.key }.map(\.value)
        handles.removeAll()
        for handle in ordered {
            await handle()
        }
    }
}
