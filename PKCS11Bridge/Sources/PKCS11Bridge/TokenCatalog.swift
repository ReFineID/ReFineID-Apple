import CCryptoki
import CryptoTokenKit
import Foundation
import LocalAuthentication
import Security

/// Builds the registry's token and object snapshot from the keychain.
///
/// Identities published by CryptoTokenKit token extensions surface as
/// keychain items carrying a token ID; each yields a certificate, a
/// public-key, and a private-key object sharing one CKA_ID (the public
/// key hash the system stores as the application label). Only EC
/// identities are exposed; RSA follows later.
internal enum TokenCatalog {
  /// One keychain identity item: reference plus the attributes the
  /// bridge needs.
  internal struct IdentityItem {
    /// The SecIdentity reference, nil when the item carried none.
    internal let identity: SecIdentity?

    /// Keychain label, e.g. the certificate's friendly name.
    internal let label: String

    /// The public key hash the system stores as the application label;
    /// serves as CKA_ID across the identity's three objects.
    internal let keyID: Data
  }

  /// One object record before handle assignment.
  internal struct Blueprint {
    /// CKO_CERTIFICATE, CKO_PUBLIC_KEY, or CKO_PRIVATE_KEY.
    internal let objectClass: CK_OBJECT_CLASS

    /// Precomputed attribute values.
    internal let attributes: [CK_ATTRIBUTE_TYPE: Data]

    /// EC field width in bytes; zero on the certificate.
    internal let fieldWidth: Int

    /// The signing key on the private-key object.
    internal let privateKey: SecKey?
  }

  /// Apple's Secure Enclave tokens carry this prefix; they are not
  /// smartcards and are not exposed as slots.
  private static let secureEnclaveTokenPrefix = "com.apple.setoken"

  /// Refreshes the token list from CryptoTokenKit, keeping slot and
  /// object numbering plus login state stable across calls.
  internal static func refresh(_ registry: inout ModuleRegistry) {
    let watcher = TKTokenWatcher()
    var tokens: [ModuleRegistry.TokenRecord] = []
    let smartcardTokenIDs = watcher.tokenIDs.filter { tokenID in
      !tokenID.hasPrefix(secureEnclaveTokenPrefix)
    }
    for tokenID in smartcardTokenIDs {
      let slotID: CK_SLOT_ID
      if let assigned = registry.slotNumbers[tokenID] {
        slotID = assigned
      } else {
        slotID = registry.nextSlotID
        registry.nextSlotID += 1
        registry.slotNumbers[tokenID] = slotID
      }
      let label = watcher.tokenInfo(forTokenID: tokenID)?.slotName ?? tokenID
      var record = ModuleRegistry.TokenRecord(
        slotID: slotID,
        tokenID: tokenID,
        label: label,
        objects: [])
      if let previous = registry.token(slotID: slotID) {
        record.loggedIn = previous.loggedIn
        record.authenticationContext = previous.authenticationContext
      }
      record.objects = objects(tokenID: tokenID, registry: &registry)
      tokens.append(record)
    }
    registry.tokens = tokens
  }

  /// Fetches the private key bound to a PIN-carrying authentication
  /// context, for tokens logged in with an explicit PIN.
  internal static func authenticatedKey(
    tokenID: String, keyID: Data, context: LAContext
  ) -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrTokenID as String: tokenID,
      kSecAttrApplicationLabel as String: keyID,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnRef as String: true,
      kSecUseAuthenticationContext as String: context,
      kSecUseDataProtectionKeychain as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
      return nil
    }
    guard let result, CFGetTypeID(result) == SecKeyGetTypeID() else { return nil }
    return unsafeDowncast(result, to: SecKey.self)
  }

  /// Builds the object records for one token's identities.
  private static func objects(
    tokenID: String, registry: inout ModuleRegistry
  ) -> [ModuleRegistry.ObjectRecord] {
    var records: [ModuleRegistry.ObjectRecord] = []
    for item in identities(tokenID: tokenID) {
      records += identityRecords(item: item, tokenID: tokenID, registry: &registry)
    }
    return records
  }

  /// Builds the three object records for one identity, or none when it
  /// is not a supported EC identity.
  private static func identityRecords(
    item: IdentityItem, tokenID: String, registry: inout ModuleRegistry
  ) -> [ModuleRegistry.ObjectRecord] {
    guard let identity = item.identity,
      let certificate = copyCertificate(identity),
      let publicKey = SecCertificateCopyKey(certificate),
      let point = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
      let width = EcEncoding.fieldWidth(uncompressedPoint: point),
      let parameters = EcEncoding.parameters(fieldWidth: width),
      let privateKey = copyPrivateKey(identity)
    else { return [] }
    let common: [CK_ATTRIBUTE_TYPE: Data] = [
      CKA_TOKEN: flag(true),
      CKA_PRIVATE: flag(false),
      CKA_MODIFIABLE: flag(false),
      CKA_LABEL: Data(displayLabel(item: item, certificate: certificate).utf8),
      CKA_ID: item.keyID,
    ]
    let blueprints = [
      Blueprint(
        objectClass: CKO_CERTIFICATE,
        attributes: certificateAttributes(common: common, certificate: certificate),
        fieldWidth: 0,
        privateKey: nil),
      Blueprint(
        objectClass: CKO_PUBLIC_KEY,
        attributes: publicKeyAttributes(
          common: common, parameters: parameters, point: point),
        fieldWidth: width,
        privateKey: nil),
      Blueprint(
        objectClass: CKO_PRIVATE_KEY,
        attributes: privateKeyAttributes(common: common, parameters: parameters),
        fieldWidth: width,
        privateKey: privateKey),
    ]
    return blueprints.map { blueprint in
      ModuleRegistry.ObjectRecord(
        handle: stableHandle(
          tokenID: tokenID,
          objectClass: blueprint.objectClass,
          keyID: item.keyID,
          registry: &registry),
        objectClass: blueprint.objectClass,
        attributes: blueprint.attributes,
        fieldWidth: blueprint.fieldWidth,
        privateKey: blueprint.privateKey)
    }
  }

  /// CKA_LABEL for one identity's objects.
  ///
  /// The certificate holder from the subject, then the token's own key
  /// name. OpenSSH shows this verbatim as the public key comment.
  private static func displayLabel(
    item: IdentityItem, certificate: SecCertificate
  ) -> String {
    guard let subject = SecCertificateCopySubjectSummary(certificate) as String? else {
      return item.label
    }
    return "\(subject) - \(item.label)"
  }

  /// Certificate-object attributes.
  private static func certificateAttributes(
    common: [CK_ATTRIBUTE_TYPE: Data], certificate: SecCertificate
  ) -> [CK_ATTRIBUTE_TYPE: Data] {
    var values = common.merging([
      CKA_CLASS: word(CKO_CERTIFICATE),
      CKA_CERTIFICATE_TYPE: word(CKC_X_509),
      CKA_VALUE: SecCertificateCopyData(certificate) as Data,
    ]) { _, new in new }
    if let subject = SecCertificateCopyNormalizedSubjectSequence(certificate) {
      values[CKA_SUBJECT] = subject as Data
    }
    if let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) {
      values[CKA_ISSUER] = issuer as Data
    }
    if let serial = SecCertificateCopySerialNumberData(certificate, nil) {
      values[CKA_SERIAL_NUMBER] = serial as Data
    }
    return values
  }

  /// Public-key-object attributes.
  private static func publicKeyAttributes(
    common: [CK_ATTRIBUTE_TYPE: Data], parameters: Data, point: Data
  ) -> [CK_ATTRIBUTE_TYPE: Data] {
    common.merging([
      CKA_CLASS: word(CKO_PUBLIC_KEY),
      CKA_KEY_TYPE: word(CKK_EC),
      CKA_EC_PARAMS: parameters,
      CKA_EC_POINT: EcEncoding.wrappedPoint(point),
      CKA_VERIFY: flag(true),
    ]) { _, new in new }
  }

  /// Private-key-object attributes.
  private static func privateKeyAttributes(
    common: [CK_ATTRIBUTE_TYPE: Data], parameters: Data
  ) -> [CK_ATTRIBUTE_TYPE: Data] {
    common.merging([
      CKA_CLASS: word(CKO_PRIVATE_KEY),
      CKA_KEY_TYPE: word(CKK_EC),
      CKA_EC_PARAMS: parameters,
      CKA_SIGN: flag(true),
      CKA_SENSITIVE: flag(true),
      CKA_ALWAYS_AUTHENTICATE: flag(false),
    ]) { _, new in new }
  }

  /// Lists the keychain identities carried by one token.
  private static func identities(tokenID: String) -> [IdentityItem] {
    // Token items live in the data-protection keychain; without the
    // explicit domain the search covers file keychains only and finds
    // nothing.
    let query: [String: Any] = [
      kSecClass as String: kSecClassIdentity,
      kSecAttrTokenID as String: tokenID,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnRef as String: true,
      kSecReturnAttributes as String: true,
      kSecUseDataProtectionKeychain as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let items = result as? [[String: Any]]
    else { return [] }
    return items.compactMap { attributes in
      guard let keyID = attributes[kSecAttrApplicationLabel as String] as? Data else {
        return nil
      }
      let reference = attributes[kSecValueRef as String] as CFTypeRef?
      let identity: SecIdentity?
      if let reference, CFGetTypeID(reference) == SecIdentityGetTypeID() {
        identity = unsafeDowncast(reference, to: SecIdentity.self)
      } else {
        identity = nil
      }
      let label = attributes[kSecAttrLabel as String] as? String ?? tokenID
      return IdentityItem(identity: identity, label: label, keyID: keyID)
    }
  }

  /// Assigns or recalls the handle for one object, stable across
  /// refreshes.
  private static func stableHandle(
    tokenID: String,
    objectClass: CK_OBJECT_CLASS,
    keyID: Data,
    registry: inout ModuleRegistry
  ) -> CK_OBJECT_HANDLE {
    let numberKey = "\(tokenID)/\(objectClass)/\(keyID.base64EncodedString())"
    if let assigned = registry.objectNumbers[numberKey] {
      return assigned
    }
    let handle = registry.nextObjectHandle
    registry.nextObjectHandle += 1
    registry.objectNumbers[numberKey] = handle
    return handle
  }

  /// SecIdentityCopyCertificate as an optional-returning call.
  private static func copyCertificate(_ identity: SecIdentity) -> SecCertificate? {
    var certificate: SecCertificate?
    guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess else {
      return nil
    }
    return certificate
  }

  /// SecIdentityCopyPrivateKey as an optional-returning call.
  private static func copyPrivateKey(_ identity: SecIdentity) -> SecKey? {
    var key: SecKey?
    guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess else { return nil }
    return key
  }

  /// A CK_ULONG attribute value in the process's native layout.
  private static func word(_ value: CK_ULONG) -> Data {
    withUnsafeBytes(of: value) { Data($0) }
  }

  /// A CK_BBOOL attribute value.
  private static func flag(_ value: Bool) -> Data {
    Data([value ? CK_TRUE : CK_FALSE])
  }
}
