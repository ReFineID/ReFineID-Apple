#include "PcscCardReset.h"

#include <TargetConditionals.h>

#if TARGET_OS_OSX

#include <PCSC/winscard.h>

bool CardCoreResetCard(const char *readerName) {
  SCARDCONTEXT context = 0;
  if (SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &context) !=
      SCARD_S_SUCCESS) {
    return false;
  }
  SCARDHANDLE card = 0;
  uint32_t activeProtocol = 0;
  bool reset = false;
  if (SCardConnect(context, readerName, SCARD_SHARE_SHARED,
                   SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &card,
                   &activeProtocol) == SCARD_S_SUCCESS) {
    reset = SCardDisconnect(card, SCARD_RESET_CARD) == SCARD_S_SUCCESS;
  }
  SCardReleaseContext(context);
  return reset;
}

#else

bool CardCoreResetCard(const char *readerName) {
  (void)readerName;
  return false;
}

#endif
