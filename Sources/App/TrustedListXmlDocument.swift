#if os(macOS)

  import Foundation
  @preconcurrency import libxml2

  /// A non-networked libxml2 document used by the XMLDSig boundary.
  internal final class TrustedListXmlDocument {
    /// One non-optional libxml element pointer.
    internal typealias Node = UnsafeMutablePointer<xmlNode>

    /// The namespace URI assigned to the xml prefix.
    private static let xmlNamespace = "http://www.w3.org/XML/1998/namespace"

    /// The parsed document, owned until this wrapper is released.
    internal let document: UnsafeMutablePointer<xmlDoc>

    /// The document element.
    internal let root: Node

    /// Parses XML without substituting entities or loading a DTD.
    internal init(_ encoded: Data) throws {
      guard !encoded.isEmpty, encoded.count <= Int(Int32.max) else {
        throw TrustedListXmlSignature.Failure.malformed
      }
      let options = Int32(
        XML_PARSE_NONET.rawValue
          | XML_PARSE_NOERROR.rawValue
          | XML_PARSE_NOWARNING.rawValue
          | XML_PARSE_COMPACT.rawValue
      )
      let parsedDocument = encoded.withUnsafeBytes { bytes in
        xmlReadMemory(
          bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
          Int32(bytes.count),
          nil,
          nil,
          options
        )
      }
      guard
        let parsedDocument,
        parsedDocument.pointee.intSubset == nil,
        parsedDocument.pointee.extSubset == nil,
        let rootNode = xmlDocGetRootElement(parsedDocument)
      else {
        if let parsedDocument {
          xmlFreeDoc(parsedDocument)
        }
        throw TrustedListXmlSignature.Failure.malformed
      }
      self.document = parsedDocument
      self.root = rootNode
    }

    /// The value of one libxml attribute.
    private static func attributeValue(
      _ attribute: UnsafeMutablePointer<xmlAttr>,
      in document: UnsafeMutablePointer<xmlDoc>
    ) -> String? {
      guard
        let value = xmlNodeListGetString(
          document, attribute.pointee.children, 1
        )
      else {
        return nil
      }
      defer { xmlFree(value) }
      return Self.string(value)
    }

    /// A Swift string copied from libxml's UTF-8 bytes.
    private static func string(
      _ value: UnsafePointer<xmlChar>?
    ) -> String? {
      guard let value else { return nil }
      return String(
        cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self)
      )
    }

    /// Direct element children.
    internal func children(of node: Node) -> [Node] {
      var found: [Node] = []
      var candidate = node.pointee.children
      while let current = candidate {
        if current.pointee.type == XML_ELEMENT_NODE {
          found.append(current)
        }
        candidate = current.pointee.next
      }
      return found
    }

    /// The element and every descendant element in document order.
    internal func descendants(including node: Node) -> [Node] {
      var found: [Node] = []
      var pending = [node]
      while let current = pending.popLast() {
        found.append(current)
        pending.append(contentsOf: children(of: current).reversed())
      }
      return found
    }

    /// Whether an element has the expected local name and namespace.
    internal func matches(
      _ node: Node,
      name: String
    ) -> Bool {
      Self.string(node.pointee.name) == name
    }

    /// Whether an element has the expected local name and namespace.
    internal func matches(
      _ node: Node,
      name: String,
      namespace: String
    ) -> Bool {
      guard Self.string(node.pointee.name) == name else { return false }
      return Self.string(node.pointee.ns?.pointee.href) == namespace
    }

    /// One unqualified attribute value, or nil when absent.
    internal func attribute(_ name: String, of node: Node) -> String? {
      var candidate = node.pointee.properties
      while let current = candidate {
        if current.pointee.ns == nil,
          Self.string(current.pointee.name) == name
        {
          return Self.attributeValue(current, in: document)
        }
        candidate = current.pointee.next
      }
      return nil
    }

    /// Every attribute whose local name is Id, ID, id, or xml:id.
    internal func identifierValues(of node: Node) -> [String] {
      var found: [String] = []
      var candidate = node.pointee.properties
      while let current = candidate {
        let name = Self.string(current.pointee.name)
        let namespace = Self.string(current.pointee.ns?.pointee.href)
        let isIdentifier =
          namespace == nil
          && ["Id", "ID", "id"].contains(name)
          || (name == "id" && namespace == Self.xmlNamespace)
        if isIdentifier,
          let value = Self.attributeValue(current, in: document)
        {
          found.append(value)
        }
        candidate = current.pointee.next
      }
      return found
    }

    /// Concatenated text content, trimmed only at the outer boundary.
    internal func text(of node: Node) -> String? {
      guard let content = xmlNodeGetContent(node) else { return nil }
      defer { xmlFree(content) }
      return Self.string(content)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    deinit {
      xmlFreeDoc(document)
    }
  }

#endif
