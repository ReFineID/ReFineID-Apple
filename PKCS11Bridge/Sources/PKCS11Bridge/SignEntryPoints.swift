import CCryptoki
import Foundation
import Security

/// Signing entry points (spec section 5.13): single-part CKM_ECDSA over
/// SecKeyCreateSignature.
///
/// The mechanism input is the caller's digest and the output is raw
/// r||s, so the X9.62 DER that Security.framework produces is converted
/// by EcEncoding. The actual card work and PIN prompting happen in the
/// system token daemon; the signature call runs outside the registry
/// lock because it can block on the PIN dialog.
internal enum SignEntryPoints {
  /// A raw ECDSA signature concatenates two field-width halves.
  private static let signatureHalves = 2
  /// C_SignInit: validates mechanism and key, then arms the session.
  internal static func signInit(
    handle: CK_SESSION_HANDLE, mechanism: CK_MECHANISM_PTR?, key: CK_OBJECT_HANDLE
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let mechanism else { return CKR_ARGUMENTS_BAD }
    guard mechanism.pointee.mechanism == CKM_ECDSA else {
      return CKR_MECHANISM_INVALID
    }
    return ModuleRegistry.shared.withLock { registry in
      guard let session = registry.sessions[handle] else {
        return CKR_SESSION_HANDLE_INVALID
      }
      guard session.signKey == nil else { return CKR_OPERATION_ACTIVE }
      guard let record = registry.object(handle: key),
        record.objectClass == CKO_PRIVATE_KEY,
        let privateKey = record.privateKey
      else { return CKR_KEY_HANDLE_INVALID }
      let chosen = boundKey(
        registry: registry, session: session, record: record, fallback: privateKey)
      registry.sessions[handle]?.signKey = chosen
      registry.sessions[handle]?.signWidth = record.fieldWidth
      return CKR_OK
    }
  }

  /// C_Sign: two-call convention, then one SecKeyCreateSignature call.
  internal static func sign(
    handle: CK_SESSION_HANDLE,
    data: CK_BYTE_PTR?,
    dataLength: CK_ULONG,
    signature: CK_BYTE_PTR?,
    signatureLength: CK_ULONG_PTR?
  ) -> CK_RV {
    guard CryptokiEntryPoints.isLive else { return CKR_CRYPTOKI_NOT_INITIALIZED }
    guard let signatureLength else { return CKR_ARGUMENTS_BAD }
    // Read the armed operation; only the length query leaves it armed.
    let armed: (key: SecKey, width: Int)? = ModuleRegistry.shared.withLock { registry in
      guard let session = registry.sessions[handle], let key = session.signKey else {
        return nil
      }
      return (key, session.signWidth)
    }
    guard let armed else {
      return ModuleRegistry.shared.withLock { registry in
        registry.sessions[handle] == nil
          ? CKR_SESSION_HANDLE_INVALID : CKR_OPERATION_NOT_INITIALIZED
      }
    }
    let expected = CK_ULONG(signatureHalves * armed.width)
    guard let signature else {
      signatureLength.pointee = expected
      return CKR_OK
    }
    guard signatureLength.pointee >= expected else {
      signatureLength.pointee = expected
      return CKR_BUFFER_TOO_SMALL
    }
    defer { disarm(handle: handle) }
    guard let data, dataLength > 0 else { return CKR_DATA_LEN_RANGE }
    let digest = Data(bytes: data, count: Int(dataLength))
    var errorReference: Unmanaged<CFError>?
    let derSignature = SecKeyCreateSignature(
      armed.key, .ecdsaSignatureDigestX962, digest as CFData, &errorReference)
    guard let derSignature else {
      errorReference?.release()
      return CKR_FUNCTION_CANCELED
    }
    guard
      let raw = EcEncoding.rawSignature(
        fromDer: derSignature as Data, fieldWidth: armed.width)
    else { return CKR_GENERAL_ERROR }
    raw.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress {
        UnsafeMutableRawPointer(signature).copyMemory(from: base, byteCount: bytes.count)
      }
    }
    signatureLength.pointee = expected
    return CKR_OK
  }

  /// Picks the PIN-bound key when C_Login supplied a PIN, otherwise
  /// the snapshot key (protected authentication path).
  private static func boundKey(
    registry: ModuleRegistry,
    session: ModuleRegistry.SessionRecord,
    record: ModuleRegistry.ObjectRecord,
    fallback: SecKey
  ) -> SecKey {
    guard let token = registry.token(slotID: session.slotID),
      let context = token.authenticationContext,
      let keyID = record.attributes[CKA_ID],
      let bound = TokenCatalog.authenticatedKey(
        tokenID: token.tokenID, keyID: keyID, context: context)
    else { return fallback }
    return bound
  }

  /// Clears the armed signing operation.
  private static func disarm(handle: CK_SESSION_HANDLE) {
    ModuleRegistry.shared.withLock { registry in
      registry.sessions[handle]?.signKey = nil
      registry.sessions[handle]?.signWidth = 0
    }
  }
}

/// Exported C_SignInit; see SignEntryPoints.signInit.
@_cdecl("C_SignInit")
internal func cryptokiSignInit(
  _ handle: CK_SESSION_HANDLE, _ mechanism: CK_MECHANISM_PTR?, _ key: CK_OBJECT_HANDLE
) -> CK_RV {
  SignEntryPoints.signInit(handle: handle, mechanism: mechanism, key: key)
}

/// Exported C_Sign; see SignEntryPoints.sign.
@_cdecl("C_Sign")
internal func cryptokiSign(
  _ handle: CK_SESSION_HANDLE,
  _ data: CK_BYTE_PTR?,
  _ dataLength: CK_ULONG,
  _ signature: CK_BYTE_PTR?,
  _ signatureLength: CK_ULONG_PTR?
) -> CK_RV {
  SignEntryPoints.sign(
    handle: handle,
    data: data,
    dataLength: dataLength,
    signature: signature,
    signatureLength: signatureLength)
}
