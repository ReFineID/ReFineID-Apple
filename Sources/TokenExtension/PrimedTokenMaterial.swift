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
import Security

/// Validated material needed to mint one contactless token.
internal struct PrimedTokenMaterial {
  /// CAN that opens the card's PACE channel.
  internal let accessNumber: CardAccessNumber

  /// Parsed authentication certificate.
  internal let leaf: SecCertificate

  /// Authentication key profile derived from the certificate.
  internal let profile: CardKeyProfile

  /// Public authentication key used to verify every card signature.
  internal let publicKey: SecKey

  /// Complete PKCS#15 token serial used for security bindings.
  internal let serial: TokenSerial
}
