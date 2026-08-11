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

/// The two command APDUs a PACE run sends.
///
/// They live apart from `CommandApdu` on purpose. That type documents itself
/// as the read-only, idempotent command class -- safe to retransmit, no side
/// effect on any counter. These two are neither: MSE:Set AT and GENERAL
/// AUTHENTICATE advance a protocol state machine inside the card, and
/// resending one out of order aborts the run. Keeping them in their own,
/// internal home means the safety class of a command stays readable from its
/// type, and nothing outside PACE can reach them.
///
/// Provenance: the command builders inside the ReFineID iOS browser donor
/// `Sources/ReFineIDBrowserKit/Card/Pace.swift`.
internal enum PaceCommand {
  /// The largest data field a short-form command APDU can carry.
  private static let maximumDataLength: Int = 255

  /// `Le = 00`, the short-form maximum every GENERAL AUTHENTICATE asks for.
  private static let maximumExpectedLength = ExpectedResponseLength(
    count: ExpectedResponseLength.maximum
  )

  /// MSE:Set AT naming the PACE suite, the CAN as the password, and
  /// brainpoolP384r1 as the domain parameters.
  ///
  /// Nil only if the assembled template does not fit a short-form data
  /// field, which the fixed contents make impossible; the failable shape
  /// exists so no encoder result is force unwrapped.
  internal static func securityEnvironment() -> Data? {
    guard
      let mechanism = DerTlvRecord.encoded(
        tag: PaceValues.cryptographicMechanismReferenceTag,
        value: Data(PaceValues.protocolOidBody)
      ),
      let password = DerTlvRecord.encoded(
        tag: PaceValues.passwordReferenceTag,
        value: Data([PaceValues.passwordReferenceCan])
      ),
      let domain = DerTlvRecord.encoded(
        tag: PaceValues.domainParameterReferenceTag,
        value: Data([PaceValues.domainParameterReferenceBrainpoolP384r1])
      )
    else {
      return nil
    }
    return Self.bytes(
      header: Data([
        Iso7816Values.classInterindustry,
        Iso7816Values.insManageSecurityEnvironment,
        PaceValues.mseSetAuthenticationTemplateP1,
        PaceValues.mseSetAuthenticationTemplateP2,
      ]),
      data: mechanism + password + domain,
      expectedLength: nil
    )
  }

  /// One GENERAL AUTHENTICATE carrying an already-encoded `7C` template.
  ///
  /// `classByte` selects chaining: the first three rounds set the chaining
  /// bit, the last one clears it, and that is how the card learns the
  /// exchange is over.
  /// The two SELECT encodings tried, in order, to reach master file.
  ///
  /// Cards differ in which they accept: the first selects by file
  /// identifier, the second by name. Both were established against real
  /// cards rather than read off a specification, and the order is the
  /// order that was measured to work.
  ///
  /// Provenance: `select_mf` in the donor
  /// `crates/refineid-lib-core/src/pkcs15.rs`.
  internal static func selectMasterFileVariants() -> [Data] {
    [
      PaceValues.selectMasterFileByIdentifier,
      PaceValues.selectMasterFileByName,
    ]
  }

  internal static func generalAuthenticate(template: Data, classByte: UInt8) -> Data? {
    guard let expectedLength = Self.maximumExpectedLength else { return nil }
    return Self.bytes(
      header: Data([
        classByte,
        PaceValues.insGeneralAuthenticate,
        PaceValues.generalAuthenticateP1,
        PaceValues.generalAuthenticateP2,
      ]),
      data: template,
      expectedLength: expectedLength
    )
  }

  /// A short-form command APDU, or nil when the data field does not fit.
  private static func bytes(
    header: Data,
    data: Data,
    expectedLength: ExpectedResponseLength?
  ) -> Data? {
    guard !data.isEmpty, data.count <= Self.maximumDataLength else { return nil }
    var command = header
    command.append(UInt8(data.count))
    command.append(data)
    if let expectedLength {
      command.append(expectedLength.encodedByte)
    }
    return command
  }
}
