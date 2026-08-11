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
/// Session-scoped memory of the credential reference numbering the card
/// answered to, so one resolution serves every later command.
///
/// A reference type on purpose: `CardOperations` is a value that may be
/// handed around within one exclusive session, and the numbering is a
/// property of the card behind the session, not of any one copy of the
/// operations value. The memo is written by whichever operation resolves
/// first and read by everything after it - including the signing chain,
/// which must pick the organization form without adding a probe of its
/// own.
internal final class CredentialReferenceMemo {
  /// The numbering the card confirmed, or nil before the first probe.
  internal var resolved: CredentialReferenceSet?
}
