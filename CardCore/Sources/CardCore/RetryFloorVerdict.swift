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
/// The retry floor's decision for one PIN-bearing operation.
///
/// The cases are closed and exhaustive on purpose: a caller must switch
/// over all of them, and no case converts an unknown reading into
/// permission.
public enum RetryFloorVerdict: Equatable, Sendable {
  /// Three or more attempts remain - or the credential is already
  /// verified in this session, which proves a counter reset to its
  /// maximum (S1 v4.2 §3.5); the operation may proceed.
  case proceed

  /// Zero attempts remain: the credential is blocked; direct the user to
  /// issuer recovery.
  case refuseBlocked

  /// One or two attempts remain: refuse before prompting for or sending
  /// any credential. ReFineID never consumes a near-last attempt.
  case refuseLowAttempts

  /// The retry state was missing, malformed, stale, or unreadable: fail
  /// closed without talking to the card.
  case refuseUnreadable
}
