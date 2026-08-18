// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

// swift-tools-version: 6.3

// CardCore: the refined FINEID protocol model and card operations.
// Platform-independent Swift with no UI and no CryptoTokenKit; the app and
// the token extension both consume it.
import PackageDescription

private let package = Package(
  name: "CardCore",
  platforms: [
    .iOS("26.0"),
    .macOS("26.0"),
  ],
  products: [
    .library(name: "CardCore", targets: ["CardCore"])
  ],
  targets: [
    // The RAPP protocol engine in Swift: deterministic CBOR, the envelope
    // schema, and the Noise handshakes and transport channel. It implements
    // the vendored specification and is replayed against the vendored
    // conformance corpus, so it is built and tested on its own while the
    // generated bindings below still carry the app.
    .target(
      name: "RappEngine",
      path: "Sources/RappEngine"),
    // Generated from refineid-lib-core by the Swift release manager. RAPP is
    // a mandatory product capability; Apple targets never downgrade to the
    // retired unauthenticated relay when these bindings are unavailable.
    .binaryTarget(
      name: "ReFineIDRappFFI",
      path: "Artifacts/ReFineIDRappFFI.xcframework"),
    .target(
      name: "ReFineIDRapp",
      dependencies: ["ReFineIDRappFFI"],
      path: "Sources/ReFineIDRapp"),
    // Tests live in the Xcode project's Tests/CardCoreTests bundle target
    // so one scheme runs them locally and in Xcode Cloud.
    // They exercise the public API only.
    .target(
      name: "CardCore",
      dependencies: [
        "ObjCExceptionGuard",
        "PcscCardReset",
        "ReFineIDRapp",
      ],
      linkerSettings: [
        .linkedFramework("Security")
      ]),
    // The engine is not yet reachable from the app, so its conformance
    // replays run here rather than in the Xcode project's test bundle.
    .testTarget(
      name: "RappEngineTests",
      dependencies: ["RappEngine"],
      path: "Tests/RappEngineTests"),
    // Objective-C, because catching an Objective-C exception is a
    // thing only Objective-C can do.
    .target(name: "ObjCExceptionGuard"),
    // C, because the PCSC module is marked unimportable from Swift
    // while its C interface remains fully supported.
    .target(
      name: "PcscCardReset",
      linkerSettings: [
        .linkedFramework("PCSC", .when(platforms: [.macOS]))
      ]),
  ]
)
