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

/// Validated material needed to mint one reader-backed token.
internal struct ReaderTokenMaterial {
  /// Certificates and complete card serial read in one card session.
  internal let identity: PublishedIdentity

  /// CAN used when the reader reached the card over contactless.
  internal let accessNumber: CardAccessNumber?

  /// Parsed authentication certificate.
  internal let leaf: SecCertificate

  /// Authentication key profile derived from the certificate.
  internal let profile: CardKeyProfile

  /// Public authentication key used to verify every card signature.
  internal let publicKey: SecKey

  /// Parsed qualified-signature certificate, when the card has one.
  internal let signLeaf: SecCertificate?

  /// Qualified key profile, when the sign leaf resolved to a
  /// supported one.
  internal let signProfile: CardKeyProfile?

  /// Public qualified key used to verify every qualified signature.
  internal let signPublicKey: SecKey?

  /// Stable token identity derived from the printed card serial.
  internal let instanceID: CardInstanceIdentifier
}
