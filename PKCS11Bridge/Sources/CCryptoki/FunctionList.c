// FunctionList.c -- the exported CK_FUNCTION_LIST and the entry-point
// stubs the bridge does not implement.
//
// PKCS#11 v2.40 requires every member of CK_FUNCTION_LIST to be a valid
// pointer, so unimplemented entry points are concrete functions returning
// CKR_FUNCTION_NOT_SUPPORTED (the standard's return value for exactly
// this). C_Initialize, C_Finalize, C_GetInfo, and C_GetSlotList are
// implemented in Swift (PKCS11Bridge target) and referenced here by
// their prototypes; the linker binds them when the dynamic library or a
// test bundle is produced.

#include "include/Cryptoki.h"

CK_RV C_GetSlotInfo(CK_SLOT_ID slotID, CK_SLOT_INFO_PTR pInfo) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetTokenInfo(CK_SLOT_ID slotID, CK_TOKEN_INFO_PTR pInfo) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetMechanismList(
  CK_SLOT_ID slotID, CK_MECHANISM_TYPE_PTR pMechanismList, CK_ULONG_PTR pulCount) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetMechanismInfo(
  CK_SLOT_ID slotID, CK_MECHANISM_TYPE type, CK_MECHANISM_INFO_PTR pInfo) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_InitToken(
  CK_SLOT_ID slotID, CK_UTF8CHAR_PTR pPin, CK_ULONG ulPinLen, CK_UTF8CHAR_PTR pLabel) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_InitPIN(CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pPin, CK_ULONG ulPinLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SetPIN(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pOldPin, CK_ULONG ulOldLen,
  CK_UTF8CHAR_PTR pNewPin, CK_ULONG ulNewLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_OpenSession(
  CK_SLOT_ID slotID, CK_FLAGS flags, CK_VOID_PTR pApplication, CK_NOTIFY Notify,
  CK_SESSION_HANDLE_PTR phSession) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_CloseSession(CK_SESSION_HANDLE hSession) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_CloseAllSessions(CK_SLOT_ID slotID) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetSessionInfo(CK_SESSION_HANDLE hSession, CK_SESSION_INFO_PTR pInfo) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetOperationState(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pOperationState,
  CK_ULONG_PTR pulOperationStateLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SetOperationState(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pOperationState,
  CK_ULONG ulOperationStateLen, CK_OBJECT_HANDLE hEncryptionKey,
  CK_OBJECT_HANDLE hAuthenticationKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Login(
  CK_SESSION_HANDLE hSession, CK_USER_TYPE userType, CK_UTF8CHAR_PTR pPin,
  CK_ULONG ulPinLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Logout(CK_SESSION_HANDLE hSession) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_CreateObject(
  CK_SESSION_HANDLE hSession, CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulCount,
  CK_OBJECT_HANDLE_PTR phObject) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_CopyObject(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount, CK_OBJECT_HANDLE_PTR phNewObject) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DestroyObject(CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetObjectSize(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ULONG_PTR pulSize) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetAttributeValue(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SetAttributeValue(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_FindObjectsInit(
  CK_SESSION_HANDLE hSession, CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulCount) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_FindObjects(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE_PTR phObject,
  CK_ULONG ulMaxObjectCount, CK_ULONG_PTR pulObjectCount) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_FindObjectsFinal(CK_SESSION_HANDLE hSession) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_EncryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Encrypt(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pEncryptedData, CK_ULONG_PTR pulEncryptedDataLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_EncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_EncryptFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pLastEncryptedPart,
  CK_ULONG_PTR pulLastEncryptedPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DecryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Decrypt(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedData, CK_ULONG ulEncryptedDataLen,
  CK_BYTE_PTR pData, CK_ULONG_PTR pulDataLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DecryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DecryptFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pLastPart, CK_ULONG_PTR pulLastPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DigestInit(CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Digest(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pDigest, CK_ULONG_PTR pulDigestLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DigestUpdate(CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DigestKey(CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DigestFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pDigest, CK_ULONG_PTR pulDigestLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SignInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Sign(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SignUpdate(CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SignFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SignRecoverInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SignRecover(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_VerifyInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_Verify(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_VerifyUpdate(CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_VerifyFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_VerifyRecoverInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_VerifyRecover(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen,
  CK_BYTE_PTR pData, CK_ULONG_PTR pulDataLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DigestEncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DecryptDigestUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SignEncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DecryptVerifyUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GenerateKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount, CK_OBJECT_HANDLE_PTR phKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GenerateKeyPair(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_ATTRIBUTE_PTR pPublicKeyTemplate, CK_ULONG ulPublicKeyAttributeCount,
  CK_ATTRIBUTE_PTR pPrivateKeyTemplate, CK_ULONG ulPrivateKeyAttributeCount,
  CK_OBJECT_HANDLE_PTR phPublicKey, CK_OBJECT_HANDLE_PTR phPrivateKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_WrapKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hWrappingKey, CK_OBJECT_HANDLE hKey, CK_BYTE_PTR pWrappedKey,
  CK_ULONG_PTR pulWrappedKeyLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_UnwrapKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hUnwrappingKey, CK_BYTE_PTR pWrappedKey, CK_ULONG ulWrappedKeyLen,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_OBJECT_HANDLE_PTR phKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_DeriveKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hBaseKey,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_OBJECT_HANDLE_PTR phKey) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_SeedRandom(CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSeed, CK_ULONG ulSeedLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GenerateRandom(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pRandomData, CK_ULONG ulRandomLen) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_GetFunctionStatus(CK_SESSION_HANDLE hSession) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_CancelFunction(CK_SESSION_HANDLE hSession) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

CK_RV C_WaitForSlotEvent(CK_FLAGS flags, CK_SLOT_ID_PTR pSlot, CK_VOID_PTR pReserved) {
  return CKR_FUNCTION_NOT_SUPPORTED;
}

// The exported function list. Version macros are used directly because a
// C static initializer cannot reference const objects.
static CK_FUNCTION_LIST FunctionList = {
  .version = {CRYPTOKI_VERSION_MAJOR, CRYPTOKI_VERSION_MINOR},
  .C_Initialize = C_Initialize,
  .C_Finalize = C_Finalize,
  .C_GetInfo = C_GetInfo,
  .C_GetFunctionList = C_GetFunctionList,
  .C_GetSlotList = C_GetSlotList,
  .C_GetSlotInfo = C_GetSlotInfo,
  .C_GetTokenInfo = C_GetTokenInfo,
  .C_GetMechanismList = C_GetMechanismList,
  .C_GetMechanismInfo = C_GetMechanismInfo,
  .C_InitToken = C_InitToken,
  .C_InitPIN = C_InitPIN,
  .C_SetPIN = C_SetPIN,
  .C_OpenSession = C_OpenSession,
  .C_CloseSession = C_CloseSession,
  .C_CloseAllSessions = C_CloseAllSessions,
  .C_GetSessionInfo = C_GetSessionInfo,
  .C_GetOperationState = C_GetOperationState,
  .C_SetOperationState = C_SetOperationState,
  .C_Login = C_Login,
  .C_Logout = C_Logout,
  .C_CreateObject = C_CreateObject,
  .C_CopyObject = C_CopyObject,
  .C_DestroyObject = C_DestroyObject,
  .C_GetObjectSize = C_GetObjectSize,
  .C_GetAttributeValue = C_GetAttributeValue,
  .C_SetAttributeValue = C_SetAttributeValue,
  .C_FindObjectsInit = C_FindObjectsInit,
  .C_FindObjects = C_FindObjects,
  .C_FindObjectsFinal = C_FindObjectsFinal,
  .C_EncryptInit = C_EncryptInit,
  .C_Encrypt = C_Encrypt,
  .C_EncryptUpdate = C_EncryptUpdate,
  .C_EncryptFinal = C_EncryptFinal,
  .C_DecryptInit = C_DecryptInit,
  .C_Decrypt = C_Decrypt,
  .C_DecryptUpdate = C_DecryptUpdate,
  .C_DecryptFinal = C_DecryptFinal,
  .C_DigestInit = C_DigestInit,
  .C_Digest = C_Digest,
  .C_DigestUpdate = C_DigestUpdate,
  .C_DigestKey = C_DigestKey,
  .C_DigestFinal = C_DigestFinal,
  .C_SignInit = C_SignInit,
  .C_Sign = C_Sign,
  .C_SignUpdate = C_SignUpdate,
  .C_SignFinal = C_SignFinal,
  .C_SignRecoverInit = C_SignRecoverInit,
  .C_SignRecover = C_SignRecover,
  .C_VerifyInit = C_VerifyInit,
  .C_Verify = C_Verify,
  .C_VerifyUpdate = C_VerifyUpdate,
  .C_VerifyFinal = C_VerifyFinal,
  .C_VerifyRecoverInit = C_VerifyRecoverInit,
  .C_VerifyRecover = C_VerifyRecover,
  .C_DigestEncryptUpdate = C_DigestEncryptUpdate,
  .C_DecryptDigestUpdate = C_DecryptDigestUpdate,
  .C_SignEncryptUpdate = C_SignEncryptUpdate,
  .C_DecryptVerifyUpdate = C_DecryptVerifyUpdate,
  .C_GenerateKey = C_GenerateKey,
  .C_GenerateKeyPair = C_GenerateKeyPair,
  .C_WrapKey = C_WrapKey,
  .C_UnwrapKey = C_UnwrapKey,
  .C_DeriveKey = C_DeriveKey,
  .C_SeedRandom = C_SeedRandom,
  .C_GenerateRandom = C_GenerateRandom,
  .C_GetFunctionStatus = C_GetFunctionStatus,
  .C_CancelFunction = C_CancelFunction,
  .C_WaitForSlotEvent = C_WaitForSlotEvent,
};

CK_RV C_GetFunctionList(CK_FUNCTION_LIST_PTR_PTR ppFunctionList) {
  if (ppFunctionList == 0) {
    return CKR_ARGUMENTS_BAD;
  }
  *ppFunctionList = &FunctionList;
  return CKR_OK;
}
