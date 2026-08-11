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
import CardCore
import Foundation
import Testing

/// Activation-scheme classification, the preflight, and the
/// changed-since-manufacture flag (FINEID S4-1 §4.6, S1 v4.2 §3.15.3).
@Suite
internal struct ActivationTests {
  /// The published cutover, 13 January 2026, as its UTC midnight.
  private static let cutover = Date(timeIntervalSince1970: 1_768_262_400)

  /// One calendar day in seconds, for stepping around the cutover.
  private static let day: TimeInterval = 86_400

  @Test
  internal func issuanceDateDecidesTheScheme() {
    #expect(
      ActivationScheme.classify(issuedOn: Self.cutover - Self.day)
        == .activationCodeIsPuk
    )
    #expect(
      ActivationScheme.classify(issuedOn: Self.cutover)
        == .presetActivationPin
    )
    #expect(
      ActivationScheme.classify(issuedOn: Self.cutover + 365 * Self.day)
        == .presetActivationPin
    )
  }

  @Test
  internal func issuerCommonNameClassifiesKnownShapesOnly() {
    #expect(
      ActivationScheme.classify(
        issuerCommonName: "DVV Citizen Certificates - G4R"
      ) == .activationCodeIsPuk
    )
    #expect(
      ActivationScheme.classify(
        issuerCommonName: "DVV Citizen Certificates - G4E"
      ) == .presetActivationPin
    )
    // A future generation marker still classifies.
    #expect(
      ActivationScheme.classify(
        issuerCommonName: "DVV Citizen Certificates - G5E"
      ) == .presetActivationPin
    )
    // An organisational issuer refuses even though its marker and
    // suffix would match: S4-1 §4.6 covers citizen cards alone.
    #expect(
      ActivationScheme.classify(
        issuerCommonName: "DVV Organisational Certificates - G4R"
      ) == nil
    )
    // No generation marker, wrong suffix, or nothing at all: refuse.
    #expect(
      ActivationScheme.classify(issuerCommonName: "DVV Citizen Certificates")
        == nil
    )
    #expect(
      ActivationScheme.classify(
        issuerCommonName: "DVV Citizen Certificates - G4X"
      ) == nil
    )
    #expect(ActivationScheme.classify(issuerCommonName: "") == nil)
  }

  @Test
  internal func entryDigitCountFollowsTheScheme() {
    #expect(ActivationScheme.activationCodeIsPuk.activationEntryDigitCount == 8)
    #expect(ActivationScheme.presetActivationPin.activationEntryDigitCount == 7)
  }

  @Test
  internal func activationCodePreflightTreatsAnyLiveReadingAsActivated() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    // A live counter is evidence the slot was written to. Invalidated
    // is not: a card can be in that state before it was ever
    // activated, and treating it as prior use would withhold
    // activation from the card that needs it.
    let live: [RetryProbeOutcome] = [.remaining(five), .verified, .locked]
    for probe in live {
      #expect(
        ActivationPreflight.evaluate(
          scheme: .activationCodeIsPuk,
          pin1Probe: probe,
          pin1ChangeRecord: .unreadable
        ) == .alreadyActivated
      )
    }
    let inconclusive: [RetryProbeOutcome?] = [
      .invalidated, .noInformation, .other(0), nil,
    ]
    for probe in inconclusive {
      #expect(
        ActivationPreflight.evaluate(
          scheme: .activationCodeIsPuk,
          pin1Probe: probe,
          pin1ChangeRecord: .unreadable
        ) == .ready
      )
    }
  }

  @Test
  internal func presetPinPreflightFollowsTheChangedFlagAlone() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    // A healthy counter is the expected fresh state and proves nothing:
    // the flag dominates in every combination.
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        pin1Probe: .remaining(five),
        pin1ChangeRecord: .changed
      ) == .alreadyActivated
    )
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        pin1Probe: .remaining(five),
        pin1ChangeRecord: .unchanged
      ) == .ready
    )
    #expect(
      ActivationPreflight.evaluate(
        scheme: .presetActivationPin,
        pin1Probe: .locked,
        pin1ChangeRecord: .unreadable
      ) == .ready
    )
  }

  @Test
  internal func changedFlagParsesItsThreeAnswers() throws {
    let five = try #require(RetryCount(attemptsRemaining: 5))
    let unchanged = WireHex.data("DF210405FFA501DF2F0100")
    let changed = WireHex.data("DF210405FFA501DF2F0101")
    let unknownFlag = WireHex.data("DF210405FFA501DF2F0102")
    let absent = WireHex.data("DF210405FFA501")

    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: unchanged)
        == .unchanged
    )
    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: changed)
        == .changed
    )
    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: unknownFlag)
        == .unreadable
    )
    #expect(
      CredentialAttributes.pinChangeRecord(fromResponseBody: absent)
        == .unreadable
    )
    // The same body still answers the retry counter.
    #expect(
      CredentialAttributes.retryCounter(fromResponseBody: unchanged) == five
    )
  }
}
