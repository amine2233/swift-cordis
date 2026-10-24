# Getting started

Build a small graph: a service, a plugin that depends on it, and a hot swap.

## Add the package

```swift
.package(url: "https://github.com/amine2233/swift-cordis.git", from: "0.1.0"),
// target dependency:
.product(name: "Cordis", package: "swift-cordis")
```

## 1. Declare a service

```swift
import Cordis

enum GreetingKey: ServiceKey { typealias Value = String }

extension Context {
    var greeting: String? { self[GreetingKey.self] }
}
```

## 2. Provide it

``ServicePlugin`` turns a factory into a plugin that provides one service:

```swift
enum GreetingPlugin: ServicePlugin {
    typealias Key = GreetingKey
    typealias Config = String
    static func make(_ ctx: Context, config: String) async throws -> String { "hello \(config)" }
}
```

## 3. Consume it

```swift
enum Printer: Plugin {
    static let inject = Inject(required: [GreetingKey.self])
    static func apply(_ ctx: Context, config: Void) async throws {
        print(try ctx.require(GreetingKey.self))
        ctx.onDispose { print("printer stopped") }
    }
}
```

## 4. Run the graph

```swift
@CordisActor func run() async {
    let app = Context.root()
    let printer = await app.plugin(Printer.self)                   // .pending
    let greeting = await app.plugin(GreetingPlugin.self, "world")  // prints "hello world"
    await greeting.update("swift")                                 // "printer stopped", prints "hello swift"
    await greeting.dispose()                                       // "printer stopped", printer is .pending
    await app.dispose()
}
```

Load order does not matter: `Printer` waits for the greeting and follows it from then on.
Run `swift run cordis-demo` for a larger walkthrough.
