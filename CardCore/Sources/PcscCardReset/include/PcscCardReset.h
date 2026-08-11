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

#include <stdint.h>

/// Resets the card in the named PC/SC reader, making the system
/// re-evaluate what the card is.
///
/// C, because the PCSC module is marked unimportable from Swift while
/// its C interface remains fully supported.
///
/// Returns 0 when the reset went through, or the failing call's
/// PC/SC status.
int32_t CardCoreResetCard(const char *readerName);
