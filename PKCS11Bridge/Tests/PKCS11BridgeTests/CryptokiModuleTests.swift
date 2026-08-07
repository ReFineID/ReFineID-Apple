import CCryptoki
import Foundation
import Testing

/// Whether a reflected CK_FUNCTION_LIST member holds a non-nil value.
private func isPresent(_ value: Any) -> Bool {
  let mirror = Mirror(reflecting: value)
  guard mirror.displayStyle == .optional else { return true }
  return !mirror.children.isEmpty
}

@Suite(.serialized)
internal struct CryptokiModuleTests {
  @Test
  internal func functionListIsCompleteAndVersioned() throws {
    var listPointer: CK_FUNCTION_LIST_PTR?
    #expect(C_GetFunctionList(&listPointer) == CKR_OK)
    let list = try #require(listPointer).pointee
    #expect(list.version.major == CK_BYTE(CRYPTOKI_VERSION_MAJOR))
    #expect(list.version.minor == CK_BYTE(CRYPTOKI_VERSION_MINOR))
    for (label, value) in Mirror(reflecting: list).children where label != "version" {
      #expect(isPresent(value), "missing function list entry: \(label ?? "unlabeled")")
    }
  }

  @Test
  internal func rejectsNilFunctionListDestination() {
    #expect(C_GetFunctionList(nil) == CKR_ARGUMENTS_BAD)
  }

  @Test
  internal func lifecycleInfoSlotsAndStubs() throws {
    var info = CK_INFO()
    #expect(C_GetInfo(&info) == CKR_CRYPTOKI_NOT_INITIALIZED)

    #expect(C_Initialize(nil) == CKR_OK)
    #expect(C_Initialize(nil) == CKR_CRYPTOKI_ALREADY_INITIALIZED)

    #expect(C_GetInfo(&info) == CKR_OK)
    #expect(info.cryptokiVersion.major == CK_BYTE(CRYPTOKI_VERSION_MAJOR))
    #expect(info.cryptokiVersion.minor == CK_BYTE(CRYPTOKI_VERSION_MINOR))
    let manufacturer = try #require(
      withUnsafeBytes(of: info.manufacturerID) { raw in
        String(bytes: raw, encoding: .utf8)
      }
    )
    #expect(manufacturer.hasPrefix("ReFineID"))
    #expect(manufacturer.hasSuffix(" "))

    var slotCount = CK_ULONG(1)
    #expect(C_GetSlotList(CK_FALSE, nil, &slotCount) == CKR_OK)
    #expect(slotCount == 0)
    #expect(C_GetSlotList(CK_FALSE, nil, nil) == CKR_ARGUMENTS_BAD)

    #expect(C_OpenSession(0, 0, nil, nil, nil) == CKR_FUNCTION_NOT_SUPPORTED)
    #expect(C_Login(0, 0, nil, 0) == CKR_FUNCTION_NOT_SUPPORTED)
    #expect(C_Sign(0, nil, 0, nil, nil) == CKR_FUNCTION_NOT_SUPPORTED)

    #expect(C_Finalize(nil) == CKR_OK)
    #expect(C_Finalize(nil) == CKR_CRYPTOKI_NOT_INITIALIZED)
  }
}
