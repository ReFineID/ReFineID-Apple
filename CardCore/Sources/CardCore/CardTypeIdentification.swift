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
import Foundation

/// What a card is, as far as an answer to reset can say.
public struct CardTypeIdentification: Equatable, Sendable {
  /// How confidently the card was named.
  public enum Confidence: Equatable, Sendable {
    /// The historical bytes match a card DVV documents.
    case documented

    /// Only the platform generation matched, so the exact card is not
    /// one the table knows.
    case generationOnly
  }

  /// The name to show: a documented card, or a generation.
  public let name: String

  /// Which of the two the name is.
  public let confidence: Confidence

  /// Names the card behind `answerToReset`, or nil when nothing matches.
  ///
  /// Nil rather than a nearest guess. The whole reason this exists as a
  /// table with dates on it is that a card can be newer than the
  /// document: rounding an unknown card to the closest row would state a
  /// model number that nobody has verified, on a screen whose purpose is
  /// to say what is actually in the reader.
  public static func identify(answerToReset: Data) -> Self? {
    guard let parsed = AnswerToReset(bytes: answerToReset) else { return nil }
    let historical = parsed.historicalBytes
    if let exact = FineidCardTypeValues.exact.first(where: { candidate in
      candidate.historicalBytes == historical
    }) {
      return Self(name: exact.name, confidence: .documented)
    }
    guard
      let family = FineidCardTypeValues.families.first(where: { candidate in
        historical.starts(with: candidate.historicalPrefix)
      })
    else {
      return nil
    }
    return Self(name: family.name, confidence: .generationOnly)
  }
}
