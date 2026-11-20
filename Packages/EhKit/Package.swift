// swift-tools-version: 6.2

import PackageDescription

// Everything that is not a view lives in this package so it can be built and
// tested on the host with `swift test` (no simulator needed).
//
// Dependency direction (each target may only import the ones above it):
//
//   EhModels  →  EhParser  →  EhNetworking ┐
//            ├→  EhDatabase ───────────────┼→  EhCore  →  EhFeatures
//            └→  EhPageTranslation ────────┤
//   EhLlama  ──────────────────────────────┘
// Lets `unimplemented` dependency endpoints report issues to Swift Testing.
let issueReportingTestSupport: Target.Dependency = .product(
    name: "IssueReportingTestSupport", package: "xctest-dynamic-overlay"
)

let package = Package(
    name: "EhKit",
    platforms: [.iOS(.v18), .macOS(.v26)],
    products: [
        .library(
            name: "EhKit",
            targets: ["EhModels", "EhParser", "EhNetworking", "EhDatabase", "EhCore", "EhFeatures"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
        .package(url: "https://github.com/tid-kijyun/Kanna", from: "6.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.2"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.13.1"),
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC", from: "2.0.0-beta")
    ],
    targets: [
        // Plain value types shared by every layer. No dependencies, no UI, no localization.
        .target(name: "EhModels"),
        .testTarget(name: "EhModelsTests", dependencies: ["EhModels", "EhTestSupport"]),

        // HTML / JSON responses → EhModels.
        .target(
            name: "EhParser",
            dependencies: ["EhModels", .product(name: "Kanna", package: "Kanna")]
        ),
        .testTarget(name: "EhParserTests", dependencies: ["EhParser", "EhTestSupport"]),

        // HTTP transport, cookies, URL building, domain fronting and the typed `EhClient`.
        .target(name: "EhNetworking", dependencies: ["EhModels", "EhParser"]),
        .testTarget(name: "EhNetworkingTests", dependencies: ["EhNetworking", "EhTestSupport"]),

        // SQLite persistence (GRDB): schema, migrations, queries.
        .target(
            name: "EhDatabase",
            dependencies: ["EhModels", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "EhDatabaseTests", dependencies: ["EhDatabase", "EhTestSupport"]),

        // Page translation: models in, patches out (Core ML, Core Graphics, Core Text, ImageIO).
        // Needs no database, network or dependencies, so it builds and tests alone.
        .target(name: "EhPageTranslation", dependencies: ["EhModels"]),
        .testTarget(name: "EhPageTranslationTests", dependencies: ["EhPageTranslation"]),

        // llama.cpp as a binary: the only place one enters the package. It is built from
        // llama.cpp's tagged source by `.github/workflows/llama-framework.yml` and kept as a
        // pre-release of this repository, because the framework llama.cpp publishes has no
        // slice for the iOS Simulator.
        .binaryTarget(
            name: "LlamaFramework",
            url: "https://github.com/aalberrty/EhShoko/releases/download/llama-b12359/llama-b12359-xcframework.zip",
            checksum: "f2fff4d63aa59f77c6cbd7344e9feabff841b4e4379e6403590691864010403e"
        ),
        // A language-model file loaded through llama.cpp: tokens, generation, a stop flag.
        // Knows nothing about pages or translation.
        .target(name: "EhLlama", dependencies: ["LlamaFramework"]),
        .testTarget(name: "EhLlamaTests", dependencies: ["EhLlama"]),

        // Dependency keys, settings and UI-independent services built on the layers above.
        .target(
            name: "EhCore",
            dependencies: [
                "EhModels", "EhParser", "EhNetworking", "EhDatabase", "EhLlama",
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "OpenCC", package: "SwiftyOpenCC")
            ]
        ),
        .testTarget(name: "EhCoreTests", dependencies: ["EhCore", "EhTestSupport", issueReportingTestSupport]),

        // `@Observable` feature models that the SwiftUI views in the app target render.
        .target(
            name: "EhFeatures",
            dependencies: ["EhCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "EhFeaturesTests",
            dependencies: ["EhFeatures", "EhTestSupport", issueReportingTestSupport],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // Test-only helpers shared by the test targets: fixtures, a stub HTTP transport,
        // in-memory databases. Never linked into the app.
        .target(
            name: "EhTestSupport",
            dependencies: ["EhModels", "EhNetworking", "EhDatabase"],
            resources: [.copy("Fixtures")]
        )
    ]
)
