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
import CardCore

/// Revokes persistent automatic-signing authority on a confirmed PIN1 refusal.
extension Token {
  /// Revokes automatic signing authority after this card rejects PIN1.
  ///
  /// This path is deliberately narrower than a generic sign failure.
  /// Transport loss, PACE failure, malformed signatures, and TLS errors do
  /// not touch stored state. Only the card's VERIFY response reaches here.
  ///
  /// The rejected fingerprint and accepted-PIN memory are process state.
  /// The stored PIN and prime are persistent authority, so they are removed
  /// before the failure returns. Registration removal is queued off the CTK
  /// callback thread to avoid asking ctkd to unregister a token while ctkd is
  /// still executing that token's sign callback.
  internal func revokeAutomaticIdentityAfterPin1Rejection(
    serial: TokenSerial,
    fingerprint: PinFingerprint
  ) {
    CredentialMemory.rejectedPins.recordRejection(fingerprint)
    CredentialMemory.acceptedPin1.clear(serial: serial)

    guard CardInstanceIdentifier(tokenSerial: serial) == cardInstanceID else {
      TokenLog.error("PIN1 rejection serial did not match token instance")
      return
    }

    let representsStoredIdentity: Bool =
      switch interface {
      case .fieldWithDeadline:
        true
      case .contact, .steadyField:
        PrimeStore.contains(instanceID: cardInstanceID)
      }
    guard representsStoredIdentity else {
      TokenLog.notice("PIN1 rejected; no stored automatic identity belonged to this token")
      return
    }

    CardCredentialStore.forgetPin1()
    PrimeStore.forget(instanceID: cardInstanceID)
    PrimeStore.forgetStaged()
    TokenRegistrationRevoker.revoke(cardInstanceID, reason: .pin1Rejection)
    TokenLog.error("PIN1 rejected; stored PIN1, prime, and token registration revoked")
  }
}
