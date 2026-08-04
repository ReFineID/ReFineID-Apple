#if os(macOS)

  import Foundation
  @preconcurrency import libxml2

  extension TrustedListXmlDocument {
    /// Pointer identities visible to one C14N execution.
    private struct CanonicalizationVisibility {
      let nodes: Set<UnsafeRawPointer>
    }

    /// Constant-time visibility lookup called by libxml's linear C14N walk.
    private static let canonicalizationVisibility:
      @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<xmlNode>?,
        UnsafeMutablePointer<xmlNode>?
      ) -> Int32 = { context, node, parent in
        guard let context, let node else { return 0 }
        let visibility = context.assumingMemoryBound(
          to: CanonicalizationVisibility.self
        ).pointee
        switch node.pointee.type {
        case XML_ATTRIBUTE_NODE, XML_NAMESPACE_DECL:
          guard let parent else { return 0 }
          return visibility.nodes.contains(UnsafeRawPointer(parent)) ? 1 : 0
        default:
          return visibility.nodes.contains(UnsafeRawPointer(node)) ? 1 : 0
        }
      }

    /// Evaluates one XPath expression with a prepared context.
    private static func evaluate(
      _ expression: String,
      in context: UnsafeMutablePointer<xmlXPathContext>
    ) -> UnsafeMutablePointer<xmlXPathObject>? {
      expression.withCString { encoded in
        let pointer = UnsafeRawPointer(encoded)
          .assumingMemoryBound(to: xmlChar.self)
        return xmlXPathEvalExpression(pointer, context)
      }
    }

    /// Registers the ds prefix used by the test-oracle XPath.
    private static func registerSignatureNamespace(
      in context: UnsafeMutablePointer<xmlXPathContext>
    ) -> Bool {
      "ds".withCString { prefix in
        TrustedListXmlSignature.Xml.signatureNamespace.withCString {
          namespace in
          xmlXPathRegisterNs(
            context,
            UnsafeRawPointer(prefix).assumingMemoryBound(to: xmlChar.self),
            UnsafeRawPointer(namespace).assumingMemoryBound(to: xmlChar.self)
          ) == 0
        }
      }
    }

    /// Exclusive XML Canonicalization 1.0 for one subtree.
    ///
    /// A pointer set is prepared in one tree walk; libxml then asks a
    /// constant-time callback about each node, attribute, and namespace.
    /// For the enveloped transform, the sole ds:Signature subtree is
    /// omitted from that set.
    internal func canonicalized(
      _ node: Node,
      excludingSignature: Bool
    ) throws -> Data {
      var visibility = CanonicalizationVisibility(
        nodes: self.visibleNodes(
          in: node,
          excludingSignature: excludingSignature
        )
      )
      guard let storage = xmlBufferCreate() else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      defer { xmlBufferFree(storage) }
      guard let output = xmlOutputBufferCreateBuffer(storage, nil) else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      let result = withUnsafeMutablePointer(to: &visibility) { context in
        xmlC14NExecute(
          document,
          Self.canonicalizationVisibility,
          context,
          Int32(XML_C14N_EXCLUSIVE_1_0.rawValue),
          nil,
          0,
          output
        )
      }
      let closeResult = xmlOutputBufferClose(output)
      guard
        result >= 0,
        closeResult >= 0,
        let bytes = xmlBufferContent(storage)
      else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      return Data(bytes: bytes, count: Int(xmlBufferLength(storage)))
    }

    /// The subtree's ordinary nodes, excluding the enveloped signature.
    private func visibleNodes(
      in node: Node,
      excludingSignature: Bool
    ) -> Set<UnsafeRawPointer> {
      var visible: Set<UnsafeRawPointer> = []
      var pending = [node]
      while let current = pending.popLast() {
        if excludingSignature,
          current.pointee.type == XML_ELEMENT_NODE,
          self.matches(
            current,
            name: "Signature",
            namespace: TrustedListXmlSignature.Xml.signatureNamespace
          )
        {
          continue
        }
        visible.insert(UnsafeRawPointer(current))
        var child = current.pointee.children
        while let found = child {
          pending.append(found)
          child = found.pointee.next
        }
      }
      return visible
    }

    /// The former XPath node-set implementation, retained as a small-input
    /// test oracle for the linear callback implementation.
    internal func canonicalizedByNodeSetForTesting(
      _ node: Node,
      excludingSignature: Bool
    ) throws -> Data {
      guard let context = xmlXPathNewContext(document) else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      defer { xmlXPathFreeContext(context) }
      context.pointee.node = node
      guard Self.registerSignatureNamespace(in: context) else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      let base = ". | .//node() | .//@* | .//namespace::*"
      let expression =
        excludingSignature
        ? "(\(base))[not(ancestor-or-self::ds:Signature)]"
        : base
      guard let result = Self.evaluate(expression, in: context) else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      defer { xmlXPathFreeObject(result) }
      guard let nodes = result.pointee.nodesetval else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      var output: UnsafeMutablePointer<xmlChar>?
      let length = xmlC14NDocDumpMemory(
        document,
        nodes,
        Int32(XML_C14N_EXCLUSIVE_1_0.rawValue),
        nil,
        0,
        &output
      )
      guard length >= 0, let output else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      defer { xmlFree(output) }
      return Data(bytes: output, count: Int(length))
    }
  }

#endif
