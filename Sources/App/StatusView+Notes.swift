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

  /// The two questions the window asks about text rather than about the
  /// card: what to say while it is busy, and whether an entry could yet
  /// be a PIN.
  ///
  /// Neither reads the window's own state, so both live here and leave
  /// the view itself to the parts that do.
  extension StatusView {
    /// What the identity row and the offered features key on.
    ///
    /// Reads two observed facts - the token's publication and the
    /// slot's physical answer - so the row moves the moment either
    /// does. Here rather than in the view body only for the view
    /// type's length; it reads shared state, no private field.
    internal var availability: LoginIdentityModel.Availability {
      if LoginIdentityModel.shared.isReady {
        .ready
      } else if CardPresence.shared.isCardPresent {
        .cardWithoutIdentity
      } else {
        .noCard
      }
    }

    /// The signature style every dropped document can take.
    ///
    /// A container suits any file; a PAdES signature suits only a PDF.
    /// So a batch takes PAdES when every document is a PDF, and a
    /// container otherwise.
    internal static func sharedFormat(for urls: [URL]) -> SignatureFormat {
      let everyOneAPdf = urls.allSatisfy { url in
        SignatureFormat.available(for: url).contains(.pades)
      }
      return everyOneAPdf ? .pades : .asice
    }

    /// What the card is busy with, or nothing when it is not.
    ///
    /// Both notes live on the action row rather than in boxes of
    /// their own: that row is already there and half empty, and a
    /// section that appears and disappears steps the window every
    /// time the card is touched.
    internal static func progressNote(_ signing: SignDocumentModel) -> String? {
      if signing.working {
        return String(localized: "Signing document…")
      }
      if signing.readingStamp {
        return String(localized: "Reading the card…")
      }
      return nil
    }

    /// Whether an entry could be a PIN2 at all.
    internal static func isEntryComplete(_ entry: String) -> Bool {
      (Pin2.minimumDigitCount...Pin2.maximumDigitCount).contains(entry.count)
    }
  }

#endif
