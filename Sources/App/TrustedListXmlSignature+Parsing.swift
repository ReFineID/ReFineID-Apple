#if os(macOS)

  import Foundation
  import Security

  extension TrustedListXmlSignature {
    /// The signed validity window of one trusted list.
    internal struct Freshness {
      internal let issuedAt: Date
      internal let nextUpdate: Date
    }

    /// Reads the one constrained enveloped XAdES signature.
    internal static func parsedSignature(
      in document: TrustedListXmlDocument
    ) throws -> ParsedSignature {
      guard
        document.matches(
          document.root,
          name: "TrustServiceStatusList",
          namespace: Xml.trustedListNamespace
        )
      else {
        throw Failure.malformed
      }
      let elements = document.descendants(including: document.root)
      let signature = try Self.signatureNode(
        in: document,
        elements: elements
      )
      let identifiers = try Self.identifierMap(
        elements: elements,
        document: document
      )
      let signed = try Self.signedInformation(
        in: signature,
        identifiers: identifiers,
        document: document
      )
      let properties = try Self.checkXadesTarget(
        signature: signature,
        references: signed.referenceNodes,
        identifiers: identifiers,
        document: document
      )
      let key = try Self.keyMaterial(in: signature, document: document)
      return ParsedSignature(
        algorithm: signed.algorithm,
        binding: try Self.signerBinding(
          in: properties,
          document: document
        ),
        certificates: key.certificates,
        references: signed.references,
        signatureValue: key.signatureValue,
        signedInfo: signed.node
      )
    }

    /// Locates the sole direct-child XMLDSig Signature.
    private static func signatureNode(
      in document: TrustedListXmlDocument,
      elements: [TrustedListXmlDocument.Node]
    ) throws -> TrustedListXmlDocument.Node {
      let signatures = elements.filter { element in
        document.matches(
          element,
          name: "Signature",
          namespace: Xml.signatureNamespace
        )
      }
      guard
        signatures.count == 1,
        let signature = signatures.first,
        signature.pointee.parent == document.root
      else {
        throw Failure.wrapping
      }
      try Self.checkSignatureIsBounded(signature, document: document)
      return signature
    }

    /// Parses SignedInfo and both required same-document references.
    private static func signedInformation(
      in signature: TrustedListXmlDocument.Node,
      identifiers: [String: TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws -> SignedInformation {
      let signedInfo = try Self.soleChild(
        name: "SignedInfo",
        namespace: Xml.signatureNamespace,
        of: signature,
        document: document
      )
      let canonicalization = try Self.soleChild(
        name: "CanonicalizationMethod",
        namespace: Xml.signatureNamespace,
        of: signedInfo,
        document: document
      )
      guard
        document.attribute("Algorithm", of: canonicalization)
          == Xml.canonicalization,
        document.children(of: canonicalization).isEmpty
      else {
        throw Failure.unsupportedAlgorithm
      }
      let method = try Self.soleChild(
        name: "SignatureMethod",
        namespace: Xml.signatureNamespace,
        of: signedInfo,
        document: document
      )
      let references = try Self.signedReferences(
        in: signedInfo,
        signature: signature,
        identifiers: identifiers,
        document: document
      )
      return SignedInformation(
        algorithm: try Self.signatureAlgorithm(
          in: method,
          document: document
        ),
        node: signedInfo,
        referenceNodes: references.nodes,
        references: references.values
      )
    }

    /// Parses exactly one document and one SignedProperties reference.
    private static func signedReferences(
      in signedInfo: TrustedListXmlDocument.Node,
      signature: TrustedListXmlDocument.Node,
      identifiers: [String: TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws -> SignedReferences {
      let children = document.children(of: signedInfo)
      let referenceNodes = children.filter { child in
        document.matches(
          child,
          name: "Reference",
          namespace: Xml.signatureNamespace
        )
      }
      guard
        referenceNodes.count == Limits.referenceCount,
        children.count
          == referenceNodes.count + Limits.signedInfoFixedChildCount
      else {
        throw Failure.malformed
      }
      let references = try referenceNodes.map { referenceNode in
        try Self.reference(
          in: referenceNode,
          signature: signature,
          identifiers: identifiers,
          document: document
        )
      }
      guard
        references.filter(\.excludesSignature).count == 1,
        references.filter({ reference in !reference.excludesSignature }).count
          == 1
      else {
        throw Failure.malformed
      }
      return SignedReferences(nodes: referenceNodes, values: references)
    }

    /// Reads SignatureValue and valid embedded X.509 certificates.
    private static func keyMaterial(
      in signature: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> KeyMaterial {
      let valueNode = try Self.soleChild(
        name: "SignatureValue",
        namespace: Xml.signatureNamespace,
        of: signature,
        document: document
      )
      guard
        document.children(of: valueNode).isEmpty,
        let signatureValue = Self.base64(document.text(of: valueNode))
      else {
        throw Failure.malformed
      }
      let keyInfo = try Self.soleChild(
        name: "KeyInfo",
        namespace: Xml.signatureNamespace,
        of: signature,
        document: document
      )
      let certificateNodes = document.descendants(including: keyInfo).filter {
        node in
        document.matches(
          node,
          name: "X509Certificate",
          namespace: Xml.signatureNamespace
        )
      }
      let certificates = try certificateNodes.map { node in
        guard
          let encoded = Self.base64(document.text(of: node)),
          SecCertificateCreateWithData(nil, encoded as CFData) != nil
        else {
          throw Failure.malformed
        }
        return encoded
      }
      guard !certificates.isEmpty else { throw Failure.malformed }
      return KeyMaterial(
        certificates: certificates,
        signatureValue: signatureValue
      )
    }

    /// Parses and enforces the signed issue/next-update interval.
    internal static func freshness(
      in document: TrustedListXmlDocument,
      at validationTime: Date
    ) throws -> Freshness {
      let scheme = try Self.soleChild(
        name: "SchemeInformation",
        of: document.root,
        document: document
      )
      let issueNode = try Self.soleChild(
        name: "ListIssueDateTime",
        of: scheme,
        document: document
      )
      let nextNode = try Self.soleChild(
        name: "NextUpdate",
        of: scheme,
        document: document
      )
      let dateNode = try Self.soleChild(
        name: "dateTime",
        of: nextNode,
        document: document
      )
      guard
        let issuedAt = Self.date(document.text(of: issueNode)),
        let nextUpdate = Self.date(document.text(of: dateNode)),
        let maximumNextUpdate = Self.maximumNextUpdate(after: issuedAt),
        issuedAt < nextUpdate,
        nextUpdate <= maximumNextUpdate,
        validationTime >= issuedAt,
        validationTime < nextUpdate
      else {
        throw Failure.stale
      }
      return Freshness(issuedAt: issuedAt, nextUpdate: nextUpdate)
    }

    /// Builds the same-document ID map, rejecting ambiguity up front.
    private static func identifierMap(
      elements: [TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws -> [String: TrustedListXmlDocument.Node] {
      var identifiers: [String: TrustedListXmlDocument.Node] = [:]
      for element in elements {
        let values = document.identifierValues(of: element)
        guard values.count <= 1 else { throw Failure.wrapping }
        guard let identifier = values.first else { continue }
        guard
          !identifier.isEmpty,
          !identifier.contains(where: \.isWhitespace),
          identifiers.updateValue(element, forKey: identifier) == nil
        else {
          throw Failure.wrapping
        }
      }
      return identifiers
    }

    /// XAdES SignedProperties must bind to this exact Signature ID.
    private static func checkXadesTarget(
      signature: TrustedListXmlDocument.Node,
      references: [TrustedListXmlDocument.Node],
      identifiers: [String: TrustedListXmlDocument.Node],
      document: TrustedListXmlDocument
    ) throws -> TrustedListXmlDocument.Node {
      let signatureIds = document.identifierValues(of: signature)
      guard signatureIds.count == 1, let signatureId = signatureIds.first else {
        throw Failure.wrapping
      }
      let propertyReferences = references.filter { reference in
        document.attribute("Type", of: reference) == Xml.signedPropertiesType
      }
      guard
        propertyReferences.count == 1,
        let uri = document.attribute("URI", of: propertyReferences[0]),
        let properties = Self.resolve(uri, identifiers: identifiers),
        let qualifying = Self.ancestor(
          of: properties,
          named: "QualifyingProperties",
          before: signature,
          document: document
        ),
        document.matches(
          qualifying,
          name: "QualifyingProperties",
          namespace: Xml.xadesNamespace
        ),
        document.attribute("Target", of: qualifying) == "#\(signatureId)"
      else {
        throw Failure.wrapping
      }
      return properties
    }

    /// The first named ancestor before the supplied boundary.
    private static func ancestor(
      of node: TrustedListXmlDocument.Node,
      named name: String,
      before boundary: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) -> TrustedListXmlDocument.Node? {
      var candidate = node.pointee.parent
      while let current = candidate, current != boundary {
        if document.matches(current, name: name) { return current }
        candidate = current.pointee.parent
      }
      return nil
    }

    /// Exactly one direct element child matching a local name.
    internal static func soleChild(
      name: String,
      of parent: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> TrustedListXmlDocument.Node {
      try Self.soleChild(
        named: name,
        namespace: nil,
        of: parent,
        document: document
      )
    }

    /// Exactly one direct element child matching a name and namespace.
    internal static func soleChild(
      name: String,
      namespace: String,
      of parent: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> TrustedListXmlDocument.Node {
      try Self.soleChild(
        named: name,
        namespace: namespace,
        of: parent,
        document: document
      )
    }

    /// Shared implementation for the two sole-child constraints.
    private static func soleChild(
      named name: String,
      namespace: String?,
      of parent: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws -> TrustedListXmlDocument.Node {
      let matches = document.children(of: parent).filter { child in
        if let namespace {
          return document.matches(child, name: name, namespace: namespace)
        }
        return document.matches(child, name: name)
      }
      guard matches.count == 1, let child = matches.first else {
        throw Failure.malformed
      }
      return child
    }
  }

#endif
