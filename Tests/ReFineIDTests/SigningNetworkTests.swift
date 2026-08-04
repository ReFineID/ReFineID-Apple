import Foundation
import Testing

@testable import ReFineID

/// Direct checks for transport rules applied before a signing request reaches
/// URLSession.
@Suite
internal struct SigningNetworkTests {
  /// Every signing exchange asks the system resolver to validate DNSSEC.
  @Test
  internal func dnssecValidationIsRequired() {
    let configuration = SigningNetwork.validatedSessionConfiguration()

    #expect(configuration.requiresDNSSECValidation)
  }

  /// Only exact HTTP-family schemes with a host are accepted.
  @Test
  internal func lookalikeAndNonNetworkAddressesAreRefused() {
    for address in [
      "httpish://timestamp.example",
      "file:///tmp/timestamp",
      "https:/missing-host",
    ] {
      #expect(throws: SigningNetwork.Failure.badAddress) {
        _ = try SigningNetwork.postRequest(
          Data(),
          to: address,
          contentType: "application/timestamp-query",
          credentials: nil,
          endpoint: .authority
        )
      }
    }
  }

  /// HTTP Basic credentials must never be exposed on a plain HTTP authority,
  /// even when that address was entered in Settings.
  @Test
  internal func credentialsRequireHttps() {
    #expect(throws: SigningNetwork.Failure.insecureCredentials) {
      _ = try SigningNetwork.postRequest(
        Data(),
        to: "http://timestamp.example",
        contentType: "application/timestamp-query",
        credentials: ("account", "secret"),
        endpoint: .authority
      )
    }
  }

  /// A public authority may use the plain HTTP endpoint published in its
  /// trusted-list service information; only credentials are barred.
  @Test
  internal func publicHttpRequestIsSupported() throws {
    let request = try SigningNetwork.postRequest(
      Data("request".utf8),
      to: "http://timestamp.example/path",
      contentType: "application/timestamp-query",
      credentials: nil,
      endpoint: .authority
    )

    #expect(request.url?.scheme == "http")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
  }

  /// HTTPS carries the exact body, type, and Basic authorization value that
  /// the caller supplied.
  @Test
  internal func httpsRequestCarriesCredentials() throws {
    let body = Data("request".utf8)
    let request = try SigningNetwork.postRequest(
      body,
      to: "https://timestamp.example/path",
      contentType: "application/timestamp-query",
      credentials: ("account", "secret"),
      endpoint: .authority
    )

    #expect(request.url?.absoluteString == "https://timestamp.example/path")
    #expect(request.httpMethod == "POST")
    #expect(request.httpBody == body)
    #expect(
      request.value(forHTTPHeaderField: "Authorization")
        == "Basic YWNjb3VudDpzZWNyZXQ="
    )
  }

  /// Authenticated timestamp requests can move only within their original
  /// HTTPS origin, which prevents an HTTPS-to-HTTP or cross-origin leak.
  @Test
  internal func credentialedRedirectsStayOnTheirHttpsOrigin() {
    guard
      let initial = URL(string: "https://tsa.example/request"),
      let sameOrigin = URL(string: "https://tsa.example:443/moved"),
      let insecure = URL(string: "http://tsa.example/moved"),
      let otherOrigin = URL(string: "https://other.example/moved")
    else {
      Issue.record("Test URL did not parse")
      return
    }

    #expect(
      SigningNetwork.redirectDecision(
        from: initial,
        to: sameOrigin,
        endpoint: .authority,
        carriesCredentials: true,
        redirectsFollowed: 0
      ) == .follow
    )
    #expect(
      SigningNetwork.redirectDecision(
        from: initial,
        to: insecure,
        endpoint: .authority,
        carriesCredentials: true,
        redirectsFollowed: 0
      ) == .refuse
    )
    #expect(
      SigningNetwork.redirectDecision(
        from: initial,
        to: otherOrigin,
        endpoint: .authority,
        carriesCredentials: true,
        redirectsFollowed: 0
      ) == .refuse
    )
    #expect(
      SigningNetwork.redirectDecision(
        from: initial,
        to: sameOrigin,
        endpoint: .authority,
        carriesCredentials: true,
        redirectsFollowed: 1
      ) == .refuse
    )
  }

  /// A credential-free timestamp request may follow a path move or an HTTPS
  /// upgrade on the configured authority, but never a downgrade or another
  /// host.
  @Test
  internal func authorityRedirectsCannotBecomeCrossHostPostRelays() {
    guard
      let plain = URL(string: "http://tsa.example/request"),
      let sameOrigin = URL(string: "http://tsa.example/moved"),
      let upgrade = URL(string: "https://tsa.example/moved"),
      let protected = URL(string: "https://tsa.example/request"),
      let downgrade = URL(string: "http://tsa.example/moved"),
      let otherHost = URL(string: "https://other.example/moved")
    else {
      Issue.record("Test URL did not parse")
      return
    }

    for target in [sameOrigin, upgrade] {
      #expect(
        SigningNetwork.redirectDecision(
          from: plain,
          to: target,
          endpoint: .authority,
          carriesCredentials: false,
          redirectsFollowed: 0
        ) == .follow
      )
    }
    for target in [downgrade, otherHost] {
      #expect(
        SigningNetwork.redirectDecision(
          from: protected,
          to: target,
          endpoint: .authority,
          carriesCredentials: false,
          redirectsFollowed: 0
        ) == .refuse
      )
    }
  }
}
