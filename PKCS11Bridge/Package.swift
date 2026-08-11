// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// swift-tools-version: 6.3

// PKCS11Bridge: a PKCS#11 v2.40 module over CryptoTokenKit and
// Security.framework. It never touches the card: identities come from
// SecItemCopyMatching and signatures from SecKeyCreateSignature, so the
// system token daemon and the ReFineID token extension do all card work.
// Consumers: Java SunPKCS11, Firefox/NSS, OpenSSH.
import PackageDescription

private let package = Package(
  name: "PKCS11Bridge",
  platforms: [
    .macOS("26.0")
  ],
  products: [
    .library(name: "PKCS11Bridge", type: .dynamic, targets: ["PKCS11Bridge"])
  ],
  targets: [
    // The PKCS#11 C ABI: type/constant subset, all 68 entry-point
    // prototypes, the exported function list, and stubs for the
    // entry points the bridge does not implement.
    .target(name: "CCryptoki"),
    // The implemented entry points, exported with C names via @_cdecl.
    .target(name: "PKCS11Bridge", dependencies: ["CCryptoki"]),
    .testTarget(name: "PKCS11BridgeTests", dependencies: ["PKCS11Bridge", "CCryptoki"]),
  ]
)
