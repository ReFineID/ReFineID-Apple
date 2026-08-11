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

#if os(macOS)

  import CardCore
  import Foundation

  /// Best-effort parent material above an already authenticated anchor.
  extension ValidationMaterialCollector {
    /// Adds available parent certificates and status without changing the
    /// strict trust result already established below `anchor`.
    internal static func enrichAboveAnchor(
      _ anchor: Data,
      at referenceDate: Date,
      evidenceTime: Date,
      collection: inout Collection,
      dependencies: Dependencies
    ) async {
      var current = anchor
      var visited: Set<Data> = []
      for _ in 0..<Self.maximumDepth {
        guard
          visited.insert(current).inserted,
          let facts = CertificateFacts(der: current),
          let parent = try? await Self.issuer(
            of: current,
            facts: facts,
            at: referenceDate,
            collection: &collection,
            dependencies: dependencies
          )
        else { return }
        collection.addCertificate(parent)
        if !collection.checked.contains(current),
          let evidence = try? await Self.status(
            of: current,
            facts: facts,
            under: parent,
            at: evidenceTime,
            dependencies: dependencies
          )
        {
          collection.checked.insert(current)
          Self.add(evidence, to: &collection)
        }
        current = parent
      }
    }

    /// Adds one authenticated best-effort status object.
    private static func add(
      _ evidence: StatusEvidence,
      to collection: inout Collection
    ) {
      switch evidence {
      case .ocsp(let response):
        collection.addOcsp(response)
      case .revocationList(let list):
        collection.addRevocationList(list)
      }
    }
  }

#endif
