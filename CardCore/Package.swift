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
    // Tests live in the Xcode project's Tests/CardCoreTests bundle target
    // so one scheme runs them locally and in Xcode Cloud.
    // They exercise the public API only.
    .target(name: "CardCore")
  ]
)
