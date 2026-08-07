// Cryptoki.h -- minimal PKCS#11 v2.40 ABI subset for the ReFineID bridge.
//
// Hand-written against the OASIS standard "PKCS #11 Cryptographic Token
// Interface Base Specification Version 2.40" and the header material it
// normatively defines (pkcs11t.h types and constants, pkcs11f.h function
// prototypes). Unix ABI: CK_ULONG is unsigned long and structures use
// default alignment (the 1-byte packing requirement applies to Windows
// only). Only what the bridge implements or must carry in
// CK_FUNCTION_LIST is declared here.

#ifndef REFINEID_CRYPTOKI_H
#define REFINEID_CRYPTOKI_H

// The Cryptoki version this module implements, used in compile-time
// constant initializers (object-like macros, as in the OASIS headers,
// because C static initializers cannot reference const objects).
#define CRYPTOKI_VERSION_MAJOR 2
#define CRYPTOKI_VERSION_MINOR 40

// -- Basic types (pkcs11t.h) --

typedef unsigned char CK_BYTE;
typedef CK_BYTE CK_CHAR;
typedef CK_BYTE CK_UTF8CHAR;
typedef CK_BYTE CK_BBOOL;
typedef unsigned long CK_ULONG;
typedef CK_ULONG CK_RV;
typedef CK_ULONG CK_FLAGS;
typedef CK_ULONG CK_SLOT_ID;
typedef CK_ULONG CK_SESSION_HANDLE;
typedef CK_ULONG CK_OBJECT_HANDLE;
typedef CK_ULONG CK_USER_TYPE;
typedef CK_ULONG CK_STATE;
typedef CK_ULONG CK_NOTIFICATION;
typedef CK_ULONG CK_MECHANISM_TYPE;
typedef CK_ULONG CK_ATTRIBUTE_TYPE;

typedef void *CK_VOID_PTR;
typedef CK_VOID_PTR *CK_VOID_PTR_PTR;
typedef CK_BYTE *CK_BYTE_PTR;
typedef CK_UTF8CHAR *CK_UTF8CHAR_PTR;
typedef CK_ULONG *CK_ULONG_PTR;
typedef CK_SLOT_ID *CK_SLOT_ID_PTR;
typedef CK_SESSION_HANDLE *CK_SESSION_HANDLE_PTR;
typedef CK_OBJECT_HANDLE *CK_OBJECT_HANDLE_PTR;
typedef CK_MECHANISM_TYPE *CK_MECHANISM_TYPE_PTR;

// -- Boolean values --

static const CK_BBOOL CK_FALSE = 0;
static const CK_BBOOL CK_TRUE = 1;

// -- Return values used by the bridge (pkcs11t.h CKR_*) --

static const CK_RV CKR_OK = 0x00000000;
static const CK_RV CKR_SLOT_ID_INVALID = 0x00000003;
static const CK_RV CKR_GENERAL_ERROR = 0x00000005;
static const CK_RV CKR_FUNCTION_FAILED = 0x00000006;
static const CK_RV CKR_ARGUMENTS_BAD = 0x00000007;
static const CK_RV CKR_FUNCTION_NOT_SUPPORTED = 0x00000054;
static const CK_RV CKR_BUFFER_TOO_SMALL = 0x00000150;
static const CK_RV CKR_CRYPTOKI_NOT_INITIALIZED = 0x00000190;
static const CK_RV CKR_CRYPTOKI_ALREADY_INITIALIZED = 0x00000191;

// -- Flags used by the bridge (pkcs11t.h CKF_*) --

// CK_C_INITIALIZE_ARGS.flags
static const CK_FLAGS CKF_LIBRARY_CANT_CREATE_OS_THREADS = 0x00000001;
static const CK_FLAGS CKF_OS_LOCKING_OK = 0x00000002;

// CK_SLOT_INFO.flags
static const CK_FLAGS CKF_TOKEN_PRESENT = 0x00000001;
static const CK_FLAGS CKF_REMOVABLE_DEVICE = 0x00000002;
static const CK_FLAGS CKF_HW_SLOT = 0x00000004;

// CK_TOKEN_INFO.flags
static const CK_FLAGS CKF_WRITE_PROTECTED = 0x00000002;
static const CK_FLAGS CKF_LOGIN_REQUIRED = 0x00000004;
static const CK_FLAGS CKF_USER_PIN_INITIALIZED = 0x00000008;
static const CK_FLAGS CKF_PROTECTED_AUTHENTICATION_PATH = 0x00000100;
static const CK_FLAGS CKF_TOKEN_INITIALIZED = 0x00000400;

// -- Structures (pkcs11t.h) --

typedef struct CK_VERSION {
  CK_BYTE major;
  CK_BYTE minor;
} CK_VERSION;

typedef struct CK_INFO {
  CK_VERSION cryptokiVersion;
  CK_UTF8CHAR manufacturerID[32];
  CK_FLAGS flags;
  CK_UTF8CHAR libraryDescription[32];
  CK_VERSION libraryVersion;
} CK_INFO;
typedef CK_INFO *CK_INFO_PTR;

typedef struct CK_SLOT_INFO {
  CK_UTF8CHAR slotDescription[64];
  CK_UTF8CHAR manufacturerID[32];
  CK_FLAGS flags;
  CK_VERSION hardwareVersion;
  CK_VERSION firmwareVersion;
} CK_SLOT_INFO;
typedef CK_SLOT_INFO *CK_SLOT_INFO_PTR;

typedef struct CK_TOKEN_INFO {
  CK_UTF8CHAR label[32];
  CK_UTF8CHAR manufacturerID[32];
  CK_UTF8CHAR model[16];
  CK_CHAR serialNumber[16];
  CK_FLAGS flags;
  CK_ULONG ulMaxSessionCount;
  CK_ULONG ulSessionCount;
  CK_ULONG ulMaxRwSessionCount;
  CK_ULONG ulRwSessionCount;
  CK_ULONG ulMaxPinLen;
  CK_ULONG ulMinPinLen;
  CK_ULONG ulTotalPublicMemory;
  CK_ULONG ulFreePublicMemory;
  CK_ULONG ulTotalPrivateMemory;
  CK_ULONG ulFreePrivateMemory;
  CK_VERSION hardwareVersion;
  CK_VERSION firmwareVersion;
  CK_CHAR utcTime[16];
} CK_TOKEN_INFO;
typedef CK_TOKEN_INFO *CK_TOKEN_INFO_PTR;

typedef struct CK_SESSION_INFO {
  CK_SLOT_ID slotID;
  CK_STATE state;
  CK_FLAGS flags;
  CK_ULONG ulDeviceError;
} CK_SESSION_INFO;
typedef CK_SESSION_INFO *CK_SESSION_INFO_PTR;

typedef struct CK_ATTRIBUTE {
  CK_ATTRIBUTE_TYPE type;
  CK_VOID_PTR pValue;
  CK_ULONG ulValueLen;
} CK_ATTRIBUTE;
typedef CK_ATTRIBUTE *CK_ATTRIBUTE_PTR;

typedef struct CK_MECHANISM {
  CK_MECHANISM_TYPE mechanism;
  CK_VOID_PTR pParameter;
  CK_ULONG ulParameterLen;
} CK_MECHANISM;
typedef CK_MECHANISM *CK_MECHANISM_PTR;

typedef struct CK_MECHANISM_INFO {
  CK_ULONG ulMinKeySize;
  CK_ULONG ulMaxKeySize;
  CK_FLAGS flags;
} CK_MECHANISM_INFO;
typedef CK_MECHANISM_INFO *CK_MECHANISM_INFO_PTR;

typedef CK_RV (*CK_NOTIFY)(
  CK_SESSION_HANDLE hSession, CK_NOTIFICATION event, CK_VOID_PTR pApplication);

typedef CK_RV (*CK_CREATEMUTEX)(CK_VOID_PTR_PTR ppMutex);
typedef CK_RV (*CK_DESTROYMUTEX)(CK_VOID_PTR pMutex);
typedef CK_RV (*CK_LOCKMUTEX)(CK_VOID_PTR pMutex);
typedef CK_RV (*CK_UNLOCKMUTEX)(CK_VOID_PTR pMutex);

typedef struct CK_C_INITIALIZE_ARGS {
  CK_CREATEMUTEX CreateMutex;
  CK_DESTROYMUTEX DestroyMutex;
  CK_LOCKMUTEX LockMutex;
  CK_UNLOCKMUTEX UnlockMutex;
  CK_FLAGS flags;
  CK_VOID_PTR pReserved;
} CK_C_INITIALIZE_ARGS;
typedef CK_C_INITIALIZE_ARGS *CK_C_INITIALIZE_ARGS_PTR;

// -- Entry-point prototypes (pkcs11f.h order) --
//
// Implemented in Swift (PKCS11Bridge target): C_Initialize, C_Finalize,
// C_GetInfo, C_GetSlotList. Implemented in C (FunctionList.c):
// C_GetFunctionList and every remaining stub.

extern CK_RV C_Initialize(CK_VOID_PTR pInitArgs);
extern CK_RV C_Finalize(CK_VOID_PTR pReserved);
extern CK_RV C_GetInfo(CK_INFO_PTR pInfo);

struct CK_FUNCTION_LIST;
typedef struct CK_FUNCTION_LIST CK_FUNCTION_LIST;
typedef CK_FUNCTION_LIST *CK_FUNCTION_LIST_PTR;
typedef CK_FUNCTION_LIST_PTR *CK_FUNCTION_LIST_PTR_PTR;
extern CK_RV C_GetFunctionList(CK_FUNCTION_LIST_PTR_PTR ppFunctionList);

extern CK_RV C_GetSlotList(
  CK_BBOOL tokenPresent, CK_SLOT_ID_PTR pSlotList, CK_ULONG_PTR pulCount);
extern CK_RV C_GetSlotInfo(CK_SLOT_ID slotID, CK_SLOT_INFO_PTR pInfo);
extern CK_RV C_GetTokenInfo(CK_SLOT_ID slotID, CK_TOKEN_INFO_PTR pInfo);
extern CK_RV C_GetMechanismList(
  CK_SLOT_ID slotID, CK_MECHANISM_TYPE_PTR pMechanismList, CK_ULONG_PTR pulCount);
extern CK_RV C_GetMechanismInfo(
  CK_SLOT_ID slotID, CK_MECHANISM_TYPE type, CK_MECHANISM_INFO_PTR pInfo);
extern CK_RV C_InitToken(
  CK_SLOT_ID slotID, CK_UTF8CHAR_PTR pPin, CK_ULONG ulPinLen, CK_UTF8CHAR_PTR pLabel);
extern CK_RV C_InitPIN(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pPin, CK_ULONG ulPinLen);
extern CK_RV C_SetPIN(
  CK_SESSION_HANDLE hSession, CK_UTF8CHAR_PTR pOldPin, CK_ULONG ulOldLen,
  CK_UTF8CHAR_PTR pNewPin, CK_ULONG ulNewLen);
extern CK_RV C_OpenSession(
  CK_SLOT_ID slotID, CK_FLAGS flags, CK_VOID_PTR pApplication, CK_NOTIFY Notify,
  CK_SESSION_HANDLE_PTR phSession);
extern CK_RV C_CloseSession(CK_SESSION_HANDLE hSession);
extern CK_RV C_CloseAllSessions(CK_SLOT_ID slotID);
extern CK_RV C_GetSessionInfo(CK_SESSION_HANDLE hSession, CK_SESSION_INFO_PTR pInfo);
extern CK_RV C_GetOperationState(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pOperationState,
  CK_ULONG_PTR pulOperationStateLen);
extern CK_RV C_SetOperationState(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pOperationState,
  CK_ULONG ulOperationStateLen, CK_OBJECT_HANDLE hEncryptionKey,
  CK_OBJECT_HANDLE hAuthenticationKey);
extern CK_RV C_Login(
  CK_SESSION_HANDLE hSession, CK_USER_TYPE userType, CK_UTF8CHAR_PTR pPin,
  CK_ULONG ulPinLen);
extern CK_RV C_Logout(CK_SESSION_HANDLE hSession);
extern CK_RV C_CreateObject(
  CK_SESSION_HANDLE hSession, CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulCount,
  CK_OBJECT_HANDLE_PTR phObject);
extern CK_RV C_CopyObject(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount, CK_OBJECT_HANDLE_PTR phNewObject);
extern CK_RV C_DestroyObject(CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject);
extern CK_RV C_GetObjectSize(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ULONG_PTR pulSize);
extern CK_RV C_GetAttributeValue(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount);
extern CK_RV C_SetAttributeValue(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hObject, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount);
extern CK_RV C_FindObjectsInit(
  CK_SESSION_HANDLE hSession, CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulCount);
extern CK_RV C_FindObjects(
  CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE_PTR phObject,
  CK_ULONG ulMaxObjectCount, CK_ULONG_PTR pulObjectCount);
extern CK_RV C_FindObjectsFinal(CK_SESSION_HANDLE hSession);
extern CK_RV C_EncryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Encrypt(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pEncryptedData, CK_ULONG_PTR pulEncryptedDataLen);
extern CK_RV C_EncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen);
extern CK_RV C_EncryptFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pLastEncryptedPart,
  CK_ULONG_PTR pulLastEncryptedPartLen);
extern CK_RV C_DecryptInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Decrypt(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedData, CK_ULONG ulEncryptedDataLen,
  CK_BYTE_PTR pData, CK_ULONG_PTR pulDataLen);
extern CK_RV C_DecryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen);
extern CK_RV C_DecryptFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pLastPart, CK_ULONG_PTR pulLastPartLen);
extern CK_RV C_DigestInit(CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism);
extern CK_RV C_Digest(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pDigest, CK_ULONG_PTR pulDigestLen);
extern CK_RV C_DigestUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_DigestKey(CK_SESSION_HANDLE hSession, CK_OBJECT_HANDLE hKey);
extern CK_RV C_DigestFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pDigest, CK_ULONG_PTR pulDigestLen);
extern CK_RV C_SignInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Sign(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_SignUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_SignFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_SignRecoverInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_SignRecover(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG_PTR pulSignatureLen);
extern CK_RV C_VerifyInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_Verify(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pData, CK_ULONG ulDataLen,
  CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen);
extern CK_RV C_VerifyUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen);
extern CK_RV C_VerifyFinal(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen);
extern CK_RV C_VerifyRecoverInit(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hKey);
extern CK_RV C_VerifyRecover(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSignature, CK_ULONG ulSignatureLen,
  CK_BYTE_PTR pData, CK_ULONG_PTR pulDataLen);
extern CK_RV C_DigestEncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen);
extern CK_RV C_DecryptDigestUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen);
extern CK_RV C_SignEncryptUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pPart, CK_ULONG ulPartLen,
  CK_BYTE_PTR pEncryptedPart, CK_ULONG_PTR pulEncryptedPartLen);
extern CK_RV C_DecryptVerifyUpdate(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pEncryptedPart, CK_ULONG ulEncryptedPartLen,
  CK_BYTE_PTR pPart, CK_ULONG_PTR pulPartLen);
extern CK_RV C_GenerateKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_ATTRIBUTE_PTR pTemplate,
  CK_ULONG ulCount, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_GenerateKeyPair(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_ATTRIBUTE_PTR pPublicKeyTemplate, CK_ULONG ulPublicKeyAttributeCount,
  CK_ATTRIBUTE_PTR pPrivateKeyTemplate, CK_ULONG ulPrivateKeyAttributeCount,
  CK_OBJECT_HANDLE_PTR phPublicKey, CK_OBJECT_HANDLE_PTR phPrivateKey);
extern CK_RV C_WrapKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hWrappingKey, CK_OBJECT_HANDLE hKey, CK_BYTE_PTR pWrappedKey,
  CK_ULONG_PTR pulWrappedKeyLen);
extern CK_RV C_UnwrapKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism,
  CK_OBJECT_HANDLE hUnwrappingKey, CK_BYTE_PTR pWrappedKey, CK_ULONG ulWrappedKeyLen,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_DeriveKey(
  CK_SESSION_HANDLE hSession, CK_MECHANISM_PTR pMechanism, CK_OBJECT_HANDLE hBaseKey,
  CK_ATTRIBUTE_PTR pTemplate, CK_ULONG ulAttributeCount, CK_OBJECT_HANDLE_PTR phKey);
extern CK_RV C_SeedRandom(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pSeed, CK_ULONG ulSeedLen);
extern CK_RV C_GenerateRandom(
  CK_SESSION_HANDLE hSession, CK_BYTE_PTR pRandomData, CK_ULONG ulRandomLen);
extern CK_RV C_GetFunctionStatus(CK_SESSION_HANDLE hSession);
extern CK_RV C_CancelFunction(CK_SESSION_HANDLE hSession);
extern CK_RV C_WaitForSlotEvent(
  CK_FLAGS flags, CK_SLOT_ID_PTR pSlot, CK_VOID_PTR pReserved);

// -- Function-pointer types and the function list (pkcs11f.h order) --

typedef CK_RV (*CK_C_Initialize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_Finalize)(CK_VOID_PTR);
typedef CK_RV (*CK_C_GetInfo)(CK_INFO_PTR);
typedef CK_RV (*CK_C_GetFunctionList)(CK_FUNCTION_LIST_PTR_PTR);
typedef CK_RV (*CK_C_GetSlotList)(CK_BBOOL, CK_SLOT_ID_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetSlotInfo)(CK_SLOT_ID, CK_SLOT_INFO_PTR);
typedef CK_RV (*CK_C_GetTokenInfo)(CK_SLOT_ID, CK_TOKEN_INFO_PTR);
typedef CK_RV (*CK_C_GetMechanismList)(CK_SLOT_ID, CK_MECHANISM_TYPE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetMechanismInfo)(
  CK_SLOT_ID, CK_MECHANISM_TYPE, CK_MECHANISM_INFO_PTR);
typedef CK_RV (*CK_C_InitToken)(CK_SLOT_ID, CK_UTF8CHAR_PTR, CK_ULONG, CK_UTF8CHAR_PTR);
typedef CK_RV (*CK_C_InitPIN)(CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SetPIN)(
  CK_SESSION_HANDLE, CK_UTF8CHAR_PTR, CK_ULONG, CK_UTF8CHAR_PTR, CK_ULONG);
typedef CK_RV (*CK_C_OpenSession)(
  CK_SLOT_ID, CK_FLAGS, CK_VOID_PTR, CK_NOTIFY, CK_SESSION_HANDLE_PTR);
typedef CK_RV (*CK_C_CloseSession)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_CloseAllSessions)(CK_SLOT_ID);
typedef CK_RV (*CK_C_GetSessionInfo)(CK_SESSION_HANDLE, CK_SESSION_INFO_PTR);
typedef CK_RV (*CK_C_GetOperationState)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SetOperationState)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_OBJECT_HANDLE, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Login)(CK_SESSION_HANDLE, CK_USER_TYPE, CK_UTF8CHAR_PTR, CK_ULONG);
typedef CK_RV (*CK_C_Logout)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_CreateObject)(
  CK_SESSION_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_CopyObject)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_DestroyObject)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_GetObjectSize)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GetAttributeValue)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SetAttributeValue)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_FindObjectsInit)(CK_SESSION_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_FindObjects)(
  CK_SESSION_HANDLE, CK_OBJECT_HANDLE_PTR, CK_ULONG, CK_ULONG_PTR);
typedef CK_RV (*CK_C_FindObjectsFinal)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_EncryptInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Encrypt)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_EncryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_EncryptFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Decrypt)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DigestInit)(CK_SESSION_HANDLE, CK_MECHANISM_PTR);
typedef CK_RV (*CK_C_Digest)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DigestUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_DigestKey)(CK_SESSION_HANDLE, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_DigestFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignInit)(CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Sign)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_SignFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignRecoverInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_SignRecover)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_VerifyInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_Verify)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyUpdate)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyFinal)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_VerifyRecoverInit)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE);
typedef CK_RV (*CK_C_VerifyRecover)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DigestEncryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptDigestUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_SignEncryptUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_DecryptVerifyUpdate)(
  CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG, CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_GenerateKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_GenerateKeyPair)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_ATTRIBUTE_PTR, CK_ULONG, CK_ATTRIBUTE_PTR,
  CK_ULONG, CK_OBJECT_HANDLE_PTR, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_WrapKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_OBJECT_HANDLE,
  CK_BYTE_PTR, CK_ULONG_PTR);
typedef CK_RV (*CK_C_UnwrapKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_BYTE_PTR, CK_ULONG,
  CK_ATTRIBUTE_PTR, CK_ULONG, CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_DeriveKey)(
  CK_SESSION_HANDLE, CK_MECHANISM_PTR, CK_OBJECT_HANDLE, CK_ATTRIBUTE_PTR, CK_ULONG,
  CK_OBJECT_HANDLE_PTR);
typedef CK_RV (*CK_C_SeedRandom)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_GenerateRandom)(CK_SESSION_HANDLE, CK_BYTE_PTR, CK_ULONG);
typedef CK_RV (*CK_C_GetFunctionStatus)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_CancelFunction)(CK_SESSION_HANDLE);
typedef CK_RV (*CK_C_WaitForSlotEvent)(CK_FLAGS, CK_SLOT_ID_PTR, CK_VOID_PTR);

struct CK_FUNCTION_LIST {
  CK_VERSION version;
  CK_C_Initialize C_Initialize;
  CK_C_Finalize C_Finalize;
  CK_C_GetInfo C_GetInfo;
  CK_C_GetFunctionList C_GetFunctionList;
  CK_C_GetSlotList C_GetSlotList;
  CK_C_GetSlotInfo C_GetSlotInfo;
  CK_C_GetTokenInfo C_GetTokenInfo;
  CK_C_GetMechanismList C_GetMechanismList;
  CK_C_GetMechanismInfo C_GetMechanismInfo;
  CK_C_InitToken C_InitToken;
  CK_C_InitPIN C_InitPIN;
  CK_C_SetPIN C_SetPIN;
  CK_C_OpenSession C_OpenSession;
  CK_C_CloseSession C_CloseSession;
  CK_C_CloseAllSessions C_CloseAllSessions;
  CK_C_GetSessionInfo C_GetSessionInfo;
  CK_C_GetOperationState C_GetOperationState;
  CK_C_SetOperationState C_SetOperationState;
  CK_C_Login C_Login;
  CK_C_Logout C_Logout;
  CK_C_CreateObject C_CreateObject;
  CK_C_CopyObject C_CopyObject;
  CK_C_DestroyObject C_DestroyObject;
  CK_C_GetObjectSize C_GetObjectSize;
  CK_C_GetAttributeValue C_GetAttributeValue;
  CK_C_SetAttributeValue C_SetAttributeValue;
  CK_C_FindObjectsInit C_FindObjectsInit;
  CK_C_FindObjects C_FindObjects;
  CK_C_FindObjectsFinal C_FindObjectsFinal;
  CK_C_EncryptInit C_EncryptInit;
  CK_C_Encrypt C_Encrypt;
  CK_C_EncryptUpdate C_EncryptUpdate;
  CK_C_EncryptFinal C_EncryptFinal;
  CK_C_DecryptInit C_DecryptInit;
  CK_C_Decrypt C_Decrypt;
  CK_C_DecryptUpdate C_DecryptUpdate;
  CK_C_DecryptFinal C_DecryptFinal;
  CK_C_DigestInit C_DigestInit;
  CK_C_Digest C_Digest;
  CK_C_DigestUpdate C_DigestUpdate;
  CK_C_DigestKey C_DigestKey;
  CK_C_DigestFinal C_DigestFinal;
  CK_C_SignInit C_SignInit;
  CK_C_Sign C_Sign;
  CK_C_SignUpdate C_SignUpdate;
  CK_C_SignFinal C_SignFinal;
  CK_C_SignRecoverInit C_SignRecoverInit;
  CK_C_SignRecover C_SignRecover;
  CK_C_VerifyInit C_VerifyInit;
  CK_C_Verify C_Verify;
  CK_C_VerifyUpdate C_VerifyUpdate;
  CK_C_VerifyFinal C_VerifyFinal;
  CK_C_VerifyRecoverInit C_VerifyRecoverInit;
  CK_C_VerifyRecover C_VerifyRecover;
  CK_C_DigestEncryptUpdate C_DigestEncryptUpdate;
  CK_C_DecryptDigestUpdate C_DecryptDigestUpdate;
  CK_C_SignEncryptUpdate C_SignEncryptUpdate;
  CK_C_DecryptVerifyUpdate C_DecryptVerifyUpdate;
  CK_C_GenerateKey C_GenerateKey;
  CK_C_GenerateKeyPair C_GenerateKeyPair;
  CK_C_WrapKey C_WrapKey;
  CK_C_UnwrapKey C_UnwrapKey;
  CK_C_DeriveKey C_DeriveKey;
  CK_C_SeedRandom C_SeedRandom;
  CK_C_GenerateRandom C_GenerateRandom;
  CK_C_GetFunctionStatus C_GetFunctionStatus;
  CK_C_CancelFunction C_CancelFunction;
  CK_C_WaitForSlotEvent C_WaitForSlotEvent;
};

#endif
