// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "iAmAwake",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "iAmAwake", targets: ["AwakeApp"]),
        .executable(name: "iamawaked", targets: ["iamawaked"]),
    ],
    targets: [
        .target(name: "AwakeCore"),
        .target(name: "PowerAssertion", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "HelperClient", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "MenuBar", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "Hotkey", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "Guards", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "Preferences", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "Notifier", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "LidObserver", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .target(name: "Overlay", dependencies: ["AwakeCore"], exclude: ["README.md"]),
        .executableTarget(name: "AwakeApp", dependencies: [
            "AwakeCore", "PowerAssertion", "HelperClient", "MenuBar",
            "Hotkey", "Guards", "Preferences", "Notifier",
            "LidObserver", "Overlay",
        ]),
        .executableTarget(name: "iamawaked", dependencies: ["AwakeCore", "HelperClient"], exclude: ["README.md"]),
        .testTarget(name: "AwakeCoreTests", dependencies: ["AwakeCore"]),
        .testTarget(name: "PowerAssertionTests", dependencies: ["PowerAssertion", "AwakeCore"]),
        .testTarget(name: "HelperClientTests", dependencies: ["HelperClient", "AwakeCore"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar", "Hotkey", "AwakeCore"]),
        .testTarget(name: "GuardsTests", dependencies: ["Guards", "AwakeCore"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences", "AwakeCore"]),
        .testTarget(name: "LidObserverTests", dependencies: ["LidObserver", "AwakeCore"]),
        .testTarget(name: "OverlayTests", dependencies: ["Overlay", "AwakeCore"]),
        .testTarget(name: "IntegrationTests", dependencies: [
            "AwakeCore", "PowerAssertion", "HelperClient", "MenuBar",
            "Hotkey", "Guards", "Preferences", "Notifier",
            "LidObserver", "Overlay",
        ]),
    ]
)
