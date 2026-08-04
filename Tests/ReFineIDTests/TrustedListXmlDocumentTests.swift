import Foundation
import Testing

@testable import ReFineID

/// Canonicalization equivalence and scaling checks for signed XML.
@Suite
internal struct TrustedListXmlDocumentTests {
  /// Large enough to expose the former quadratic XPath node-set merge.
  private static let performanceElementCount = 20_000

  /// A generous upper bound for a sub-megabyte linear canonicalization.
  private static let performanceLimit = Duration.seconds(5)

  /// Finds one uniquely named element in a test document.
  private static func uniqueNode(
    named name: String,
    namespace: String,
    in document: TrustedListXmlDocument
  ) throws -> TrustedListXmlDocument.Node {
    let nodes = document.descendants(including: document.root).filter { node in
      document.matches(node, name: name, namespace: namespace)
    }
    guard nodes.count == 1, let node = nodes.first else {
      throw TrustedListXmlSignature.Failure.malformed
    }
    return node
  }

  /// The linear visibility callback produces the same exclusive C14N
  /// bytes as the former XPath node-set implementation for every signed
  /// subtree shape used by ETSI trusted lists.
  @Test
  internal func linearCanonicalizationMatchesNodeSetOracle() throws {
    let profile = TrustedListXmlSignatureFixtures.Profile.rsaSha256
    let signer = try TrustedListXmlSignatureFixtures.makeSigner(for: profile)
    let encoded = try TrustedListXmlSignatureFixtures.signedList(
      profile: profile,
      signer: signer,
      window: .current,
      schemeContent: "<SchemeName xml:lang=\"en\">Test</SchemeName>"
    )
    let document = try TrustedListXmlDocument(encoded)
    let signedInfo = try Self.uniqueNode(
      named: "SignedInfo",
      namespace: TrustedListXmlSignature.Xml.signatureNamespace,
      in: document
    )
    let properties = try Self.uniqueNode(
      named: "SignedProperties",
      namespace: TrustedListXmlSignature.Xml.xadesNamespace,
      in: document
    )

    #expect(
      try document.canonicalized(document.root, excludingSignature: true)
        == document.canonicalizedByNodeSetForTesting(
          document.root,
          excludingSignature: true
        )
    )
    #expect(
      try document.canonicalized(signedInfo, excludingSignature: false)
        == document.canonicalizedByNodeSetForTesting(
          signedInfo,
          excludingSignature: false
        )
    )
    #expect(
      try document.canonicalized(properties, excludingSignature: false)
        == document.canonicalizedByNodeSetForTesting(
          properties,
          excludingSignature: false
        )
    )
  }

  /// Canonicalizing a wide document remains bounded in wall-clock time.
  @Test
  internal func wideDocumentCanonicalizationRemainsLinear() throws {
    let children = (0..<Self.performanceElementCount)
      .map { index in
        "<Entry index=\"\(index)\">value</Entry>"
      }
      .joined()
    let document = try TrustedListXmlDocument(
      Data("<List>\(children)</List>".utf8)
    )
    let clock = ContinuousClock()
    let started = clock.now

    let canonical = try document.canonicalized(
      document.root,
      excludingSignature: false
    )
    let elapsed = started.duration(to: clock.now)

    #expect(!canonical.isEmpty)
    #expect(elapsed < Self.performanceLimit)
  }
}
