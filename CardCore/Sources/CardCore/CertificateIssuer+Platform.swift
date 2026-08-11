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
import Security

/// Full platform validation retained ahead of the revoked-only direct fallback.
extension CertificateIssuer {
  /// Evaluates one two-certificate path with the issuer as its sole anchor.
  internal static func platformVerdict(
    subject: Parsed,
    issuer: Parsed,
    at date: Date
  ) -> PlatformVerdict {
    var trust: SecTrust?
    guard
      SecTrustCreateWithCertificates(
        [subject.certificate, issuer.certificate] as CFArray,
        SecPolicyCreateBasicX509(),
        &trust
      ) == errSecSuccess,
      let trust,
      SecTrustSetAnchorCertificates(
        trust, [issuer.certificate] as CFArray
      ) == errSecSuccess,
      SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
      SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
      SecTrustSetVerifyDate(trust, date as CFDate) == errSecSuccess
    else {
      return .rejected
    }
    var error: CFError?
    if SecTrustEvaluateWithError(trust, &error) {
      return .accepted
    }
    guard let error else { return .rejected }
    let failure = error as Error as NSError
    return failure.domain == NSOSStatusErrorDomain
      && failure.code == Int(errSecCertificateRevoked)
      ? .revoked : .rejected
  }
}
