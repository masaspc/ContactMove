// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ContactMoveKit",
    defaultLocalization: "ja",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ContactMoveKit",
            targets: ["Models", "CSVKit", "DedupeKit", "ContactsKit", "TransferKit"]
        ),
    ],
    targets: [
        // MARK: - Sources
        .target(name: "Models"),
        .target(name: "CSVKit", dependencies: ["Models"]),
        .target(name: "DedupeKit", dependencies: ["Models"]),
        .target(name: "ContactsKit", dependencies: ["Models", "DedupeKit"]),
        .target(name: "TransferKit", dependencies: ["Models"]),

        // MARK: - Tests
        .testTarget(name: "ModelsTests", dependencies: ["Models"]),
        .testTarget(name: "CSVKitTests", dependencies: ["CSVKit"], resources: [.copy("Resources")]),
        .testTarget(name: "DedupeKitTests", dependencies: ["DedupeKit"]),
        .testTarget(name: "ContactsKitTests", dependencies: ["ContactsKit"]),
        .testTarget(name: "TransferKitTests", dependencies: ["TransferKit"]),
    ]
)
