//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
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
    .target(name: "CardCore", dependencies: ["ObjCExceptionGuard", "PcscCardReset"]),
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
