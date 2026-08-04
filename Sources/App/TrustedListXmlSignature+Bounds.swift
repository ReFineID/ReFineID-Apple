#if os(macOS)

  import Foundation

  /// The bound on what an enveloped signature may carry.
  ///
  /// XMLDSig's enveloped transform removes the whole `ds:Signature`
  /// element from the bytes the digest covers. Anything inside it is
  /// therefore signed by nothing while the list around it verifies
  /// bit for bit - so a TSPService or a national-list pointer spliced
  /// in there would be read as though the signature vouched for it.
  /// The readers anchor their searches at the root to avoid looking;
  /// this makes sure there is nothing to find.
  extension TrustedListXmlSignature {
    /// Refuses a Signature carrying anything outside the profile.
    ///
    /// The enveloped transform removes this whole element from the
    /// bytes the digest covers, so anything inside it is signed by
    /// nothing while the list around it still verifies bit for bit.
    /// A TSPService or a pointer hidden here would be read as if the
    /// signature vouched for it, so there must be nowhere to hide
    /// one: only the four element names the profile defines may
    /// appear, at most one `Object`, and that one may hold only the
    /// XAdES qualifying properties - which are themselves signed,
    /// through their own reference.
    internal static func checkSignatureIsBounded(
      _ signature: TrustedListXmlDocument.Node,
      document: TrustedListXmlDocument
    ) throws {
      let permitted = ["SignedInfo", "SignatureValue", "KeyInfo", "Object"]
      let children = document.children(of: signature)
      let bounded = children.allSatisfy { child in
        permitted.contains { name in
          document.matches(child, name: name, namespace: Xml.signatureNamespace)
        }
      }
      let objects = children.filter { child in
        document.matches(child, name: "Object", namespace: Xml.signatureNamespace)
      }
      guard bounded, objects.count <= 1 else { throw Failure.wrapping }
      for object in objects {
        let held = document.children(of: object)
        guard
          held.count == 1,
          let properties = held.first,
          document.matches(
            properties,
            name: "QualifyingProperties",
            namespace: Xml.xadesNamespace
          )
        else {
          throw Failure.wrapping
        }
      }
    }
  }

#endif
