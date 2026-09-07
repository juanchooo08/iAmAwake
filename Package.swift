// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StillOnLocal",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StillOn", targets: ["StillOnApp"]),
        .executable(name: "stillond", targets: ["stillond"]),
    ],
    targets: [
        .target(name: "StillOnCore"),
        .target(name: "PowerAssertion", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .target(name: "HelperClient", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .target(name: "MenuBar", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .target(name: "Hotkey", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .target(name: "Guards", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .target(name: "Preferences", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .target(name: "Notifier", dependencies: ["StillOnCore"], exclude: ["README.md"]),
        .executableTarget(name: "StillOnApp", dependencies: [
            "StillOnCore", "PowerAssertion", "HelperClient", "MenuBar",
            "Hotkey", "Guards", "Preferences", "Notifier",
        ]),
        .executableTarget(name: "stillond", dependencies: ["StillOnCore", "HelperClient"], exclude: ["README.md"]),
        .testTarget(name: "StillOnCoreTests", dependencies: ["StillOnCore"]),
        .testTarget(name: "PowerAssertionTests", dependencies: ["PowerAssertion", "StillOnCore"]),
        .testTarget(name: "HelperClientTests", dependencies: ["HelperClient", "StillOnCore"]),
        .testTarget(name: "MenuBarTests", dependencies: ["MenuBar", "Hotkey", "StillOnCore"]),
        .testTarget(name: "GuardsTests", dependencies: ["Guards", "StillOnCore"]),
        .testTarget(name: "PreferencesTests", dependencies: ["Preferences", "StillOnCore"]),
        .testTarget(name: "IntegrationTests", dependencies: [
            "StillOnCore", "PowerAssertion", "HelperClient", "MenuBar",
            "Hotkey", "Guards", "Preferences", "Notifier",
        ]),
    ]
)
