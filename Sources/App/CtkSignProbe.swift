import CryptoKit
import CryptoTokenKit
import Foundation
import Security

/// Diagnostic that signs through the real token-extension path.
///
/// Unlike `SignProbe` (which drives the card directly), this looks up the
/// published identity's private key in the keychain and calls
/// `SecKeyCreateSignature`. That routes through the extension exactly as
/// Safari does - `supports` -> `beginAuth` (the system PIN sheet) -> `sign`
/// - then verifies the returned signature against the leaf. Launched with
/// `--ctk-sign-probe`; the PIN sheet is entered by hand on the device.
///
/// The signature runs on a background queue so the main thread returns to
/// the app run loop the system needs to present the PIN sheet.
internal enum CtkSignProbe {
  internal static func runIfRequested() {
    guard CommandLine.arguments.contains("--ctk-sign-probe") else { return }
    DispatchQueue.global().async {
      for line in collect() {
        print(line)
      }
      exit(0)
    }
  }

  private static func collect() -> [String] {
    var lines: [String] = []
    let watcher = TKTokenWatcher()
    let tokens = watcher.tokenIDs.sorted().filter { $0.hasPrefix("fi.refineid.") }
    lines.append("refineid tokens: \(tokens.count) - \(tokens.joined(separator: ", "))")
    guard let tokenID = tokens.first else {
      return lines + ["FAIL: no refineid token registered"]
    }

    guard let privateKey = copyTokenKey(tokenID: tokenID) else {
      return lines + dumpTokenKeychain() + ["FAIL: no refineid key in keychain"]
    }
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      return lines + ["FAIL: could not derive the public key"]
    }
    return lines + signThroughExtension(privateKey: privateKey, publicKey: publicKey)
  }

  private static func signThroughExtension(privateKey: SecKey, publicKey: SecKey) -> [String] {
    let digest = Data(SHA384.hash(data: Data("ReFineID CTK path test".utf8)))
    let algorithm = SecKeyAlgorithm.ecdsaSignatureDigestX962SHA384
    guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
      return ["FAIL: token key does not support the algorithm (supports said NO)"]
    }
    var error: Unmanaged<CFError>?
    let created = SecKeyCreateSignature(privateKey, algorithm, digest as CFData, &error)
    guard let signature = created as Data? else {
      let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
      return ["FAIL: SecKeyCreateSignature - \(reason)"]
    }
    var verifyError: Unmanaged<CFError>?
    let valid = SecKeyVerifySignature(
      publicKey,
      algorithm,
      digest as CFData,
      signature as CFData,
      &verifyError
    )
    guard valid else {
      let reason = verifyError?.takeRetainedValue().localizedDescription ?? "unknown"
      return ["signature: \(signature.count) B - FAIL: does not verify - \(reason)"]
    }
    return ["signature: \(signature.count) DER bytes - EXTENSION SIGN VERIFIES OK"]
  }

  /// Lists every item class in the token access group with its token ID
  /// and label, so a missing identity is diagnosable rather than silent.
  private static func dumpTokenKeychain() -> [String] {
    var lines: [String] = []
    let classes: [(CFString, String)] = [
      (kSecClassIdentity, "identity"),
      (kSecClassCertificate, "certificate"),
      (kSecClassKey, "key"),
    ]
    for (itemClass, name) in classes {
      let query: [CFString: Any] = [
        kSecClass: itemClass,
        kSecAttrAccessGroup: kSecAttrAccessGroupToken,
        kSecReturnAttributes: true,
        kSecMatchLimit: kSecMatchLimitAll,
      ]
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      guard status == errSecSuccess, let items = result as? [[CFString: Any]] else {
        lines.append("\(name): status \(status)")
        continue
      }
      lines.append("\(name): \(items.count) item(s)")
      for item in items {
        let tokenID = (item[kSecAttrTokenID] as? String) ?? "-"
        let label = (item[kSecAttrLabel] as? String) ?? "-"
        lines.append("  tokenID=\(tokenID) label=\(label)")
      }
    }
    return lines
  }

  private static func copyTokenKey(tokenID: String) -> SecKey? {
    // The token's key lives in the token access group; the query must
    // name it (and the app holds the com.apple.token keychain group
    // entitlement) or SecItemCopyMatching never returns it. Several
    // query shapes are tried in order and the working one reported -
    // iOS is picky about which attribute filters and return forms it
    // honors for token items.
    let variants: [(String, [CFString: Any])] = [
      (
        "key/ref",
        [
          kSecClass: kSecClassKey,
          kSecAttrAccessGroup: kSecAttrAccessGroupToken,
          kSecReturnRef: true,
          kSecMatchLimit: kSecMatchLimitOne,
        ]
      ),
      (
        "key/tokenID-no-group",
        [
          kSecClass: kSecClassKey,
          kSecAttrTokenID: tokenID,
          kSecReturnRef: true,
          kSecMatchLimit: kSecMatchLimitOne,
        ]
      ),
      (
        "key/attrs+ref",
        [
          kSecClass: kSecClassKey,
          kSecAttrAccessGroup: kSecAttrAccessGroupToken,
          kSecReturnAttributes: true,
          kSecReturnRef: true,
          kSecMatchLimit: kSecMatchLimitOne,
        ]
      ),
    ]
    for (name, query) in variants {
      if let key = runKeyQuery(name: name, query: query) {
        return key
      }
    }
    return nil
  }

  private static func runKeyQuery(name: String, query: [CFString: Any]) -> SecKey? {
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let found = result else {
      print("\(name): status \(status)")
      return nil
    }
    let reference: CFTypeRef
    if let attributes = found as? [CFString: Any] {
      guard let fromAttributes = attributes[kSecValueRef] else {
        print("\(name): attributes without ref (keys: \(attributes.keys.count))")
        return nil
      }
      reference = fromAttributes as CFTypeRef
    } else {
      reference = found
    }
    guard CFGetTypeID(reference) == SecKeyGetTypeID() else {
      print("\(name): non-key ref")
      return nil
    }
    print("\(name): got the key ref")
    // Type-checked immediately above; this cast cannot fail.
    return unsafeDowncast(reference as AnyObject, to: SecKey.self)
  }
}
