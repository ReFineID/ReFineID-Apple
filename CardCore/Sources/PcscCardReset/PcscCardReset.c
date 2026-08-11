// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
#include "PcscCardReset.h"

#include <TargetConditionals.h>

#if TARGET_OS_OSX

#include <PCSC/winscard.h>

int32_t CardCoreResetCard(const char *readerName) {
  SCARDCONTEXT context = 0;
  int32_t result =
      SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &context);
  if (result != SCARD_S_SUCCESS) {
    return result;
  }
  SCARDHANDLE card = 0;
  uint32_t activeProtocol = 0;
  result = SCardConnect(context, readerName, SCARD_SHARE_SHARED,
                        SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &card,
                        &activeProtocol);
  if (result == SCARD_S_SUCCESS) {
    result = SCardDisconnect(card, SCARD_RESET_CARD);
  }
  SCardReleaseContext(context);
  return result;
}

#else

int32_t CardCoreResetCard(const char *readerName) {
  (void)readerName;
  return INT32_MIN;
}

#endif
