#if os(macOS)

  import Foundation

  extension TrustedListXmlSignature {
    /// One constrained Reference and its resolved same-document target.
    internal static func reference(
      in node: TrustedListXmlDocument.Node,
      signature: TrustedListXmlDocument.Node,
      identifiers: [String: TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws -> Reference {
      let transforms = try Self.transforms(in: node, document: document)
      let target = try Self.referenceTarget(
        in: node,
        transforms: transforms,
        signature: signature,
        identifiers: identifiers,
        document: document
      )
      let algorithm = try Self.digestAlgorithm(in: node, document: document)
      let digestValue = try Self.soleChild(
        name: "DigestValue",
        namespace: Xml.signatureNamespace,
        of: node,
        document: document
      )
      guard
        document.children(of: digestValue).isEmpty,
        let expected = Self.base64(document.text(of: digestValue)),
        expected.count == Self.digestLength(for: algorithm)
      else {
        throw Failure.malformed
      }
      let expectedChildren =
        transforms.isEmpty
        ? Limits.referenceFixedChildCount
        : Limits.referenceTransformedChildCount
      guard document.children(of: node).count == expectedChildren else {
        throw Failure.malformed
      }
      return Reference(
        algorithm: algorithm,
        expectedDigest: expected,
        excludesSignature: target.excludesSignature,
        target: target.node
      )
    }

    /// Resolves the only two reference forms accepted by the profile.
    private static func referenceTarget(
      in reference: TrustedListXmlDocument.Node,
      transforms: [String],
      signature: TrustedListXmlDocument.Node,
      identifiers: [String: TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws -> ReferenceTarget {
      let type = document.attribute("Type", of: reference)
      let uri = document.attribute("URI", of: reference)
      guard let uri else { throw Failure.malformed }
      if type == Xml.signedPropertiesType {
        guard
          transforms == [Xml.canonicalization],
          let resolved = Self.resolve(uri, identifiers: identifiers),
          document.matches(
            resolved,
            name: "SignedProperties",
            namespace: Xml.xadesNamespace
          ),
          Self.isDescendant(resolved, of: signature)
        else {
          throw Failure.wrapping
        }
        return ReferenceTarget(excludesSignature: false, node: resolved)
      }
      guard
        type == nil,
        transforms == [Xml.envelopedTransform, Xml.canonicalization]
      else {
        throw Failure.unsupportedAlgorithm
      }
      if uri.isEmpty {
        return ReferenceTarget(
          excludesSignature: true,
          node: document.root
        )
      }
      guard
        let resolved = Self.resolve(uri, identifiers: identifiers),
        resolved == document.root
      else {
        throw Failure.wrapping
      }
      return ReferenceTarget(excludesSignature: true, node: resolved)
    }

    /// The supported digest method on one Reference.
    private static func digestAlgorithm(
      in reference: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> DigestAlgorithm {
      let method = try Self.soleChild(
        name: "DigestMethod",
        namespace: Xml.signatureNamespace,
        of: reference,
        document: document
      )
      guard document.children(of: method).isEmpty else {
        throw Failure.unsupportedAlgorithm
      }
      switch document.attribute("Algorithm", of: method) {
      case Xml.digestSha256:
        return .sha256
      case Xml.digestSha512:
        return .sha512
      default:
        throw Failure.unsupportedAlgorithm
      }
    }

    /// Byte count of a digest value for one supported algorithm.
    internal static func digestLength(for algorithm: DigestAlgorithm) -> Int {
      switch algorithm {
      case .sha256:
        return Limits.digestSha256Bytes
      case .sha512:
        return Limits.digestSha512Bytes
      }
    }

    /// Ordered transform algorithm URIs.
    private static func transforms(
      in reference: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> [String] {
      let containers = document.children(of: reference).filter { child in
        document.matches(
          child,
          name: "Transforms",
          namespace: Xml.signatureNamespace
        )
      }
      guard containers.count == 1, let container = containers.first else {
        throw Failure.unsupportedAlgorithm
      }
      return try document.children(of: container).map { transform in
        guard
          document.matches(
            transform,
            name: "Transform",
            namespace: Xml.signatureNamespace
          ),
          document.children(of: transform).isEmpty,
          let algorithm = document.attribute("Algorithm", of: transform)
        else {
          throw Failure.unsupportedAlgorithm
        }
        return algorithm
      }
    }

    /// Resolves a simple same-document fragment without XPointer syntax.
    internal static func resolve(
      _ uri: String,
      identifiers: [String: TrustedListXmlDocument.Node]
    ) -> TrustedListXmlDocument.Node? {
      guard
        uri.first == "#",
        uri.count > 1,
        !uri.contains("%"),
        !uri.contains("(")
      else {
        return nil
      }
      return identifiers[String(uri.dropFirst())]
    }

    /// Whether a node sits inside the supplied ancestor.
    private static func isDescendant(
      _ node: TrustedListXmlDocument.Node,
      of ancestor: TrustedListXmlDocument.Node
    ) -> Bool {
      var candidate = node.pointee.parent
      while let current = candidate {
        if current == ancestor { return true }
        candidate = current.pointee.parent
      }
      return false
    }
  }

#endif
