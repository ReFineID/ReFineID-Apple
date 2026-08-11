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

import Foundation
import Testing

@testable import ReFineID

/// The visible PDF stamp remains opt-in when it carries a portrait QR.
@Suite
internal struct DocumentStampStyleTests {
  private static func preferences() throws -> (String, UserDefaults) {
    let name = "DocumentStampStyleTests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: name))
    preferences.removePersistentDomain(forName: name)
    return (name, preferences)
  }

  @Test
  internal func noPreferenceUsesSignatureNameAndSatu() throws {
    let (name, preferences) = try Self.preferences()
    defer { preferences.removePersistentDomain(forName: name) }

    #expect(
      DocumentStampStyle.load(from: preferences) == .signatureAndIdentity
    )
    #expect(!DocumentStampStyle.load(from: preferences).readsPortrait)
  }

  @Test
  internal func portraitQrIsAnExplicitPersistentChoice() throws {
    let (name, preferences) = try Self.preferences()
    defer { preferences.removePersistentDomain(forName: name) }

    DocumentStampStyle.save(.portraitQr, to: preferences)

    #expect(DocumentStampStyle.load(from: preferences) == .portraitQr)
    #expect(DocumentStampStyle.load(from: preferences).readsPortrait)
  }

  @Test
  internal func restoringTheStandardRemovesTheOverride() throws {
    let (name, preferences) = try Self.preferences()
    defer { preferences.removePersistentDomain(forName: name) }
    DocumentStampStyle.save(.portraitQr, to: preferences)

    DocumentStampStyle.save(.signatureAndIdentity, to: preferences)

    #expect(
      DocumentStampStyle.load(from: preferences) == .signatureAndIdentity
    )
  }
}
