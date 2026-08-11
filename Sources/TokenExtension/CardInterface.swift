//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
/// How the card this token was made from is reached.
///
/// Two of these are contactless, and the difference between them decides
/// how a signature may be taken. A card on a reader's antenna sits in a
/// field the reader holds for as long as it likes, so a signature there
/// can afford everything the contact path does: read the serial, read
/// the counters, and reuse a card-bound PIN. A card held against a phone
/// does not have that: the system owns the slot, ends it about two
/// seconds after the mint, and every read spends field the signature
/// still needs -- so that path asks for the PIN before touching the card
/// and reads nothing it was not given.
///
/// Telling them apart by slot name was tried and is wrong: a reader
/// names its interfaces by a trailing index and never says which is the
/// antenna. This is recorded at the mint instead, by the code that
/// already knows which of the two ways it made the token.
internal enum CardInterface: Sendable {
  /// In a contact slot, speaking in the clear.
  case contact

  /// Held against the phone's own antenna, on the system's clock.
  case fieldWithDeadline

  /// On a reader's antenna, in a field that is not going anywhere.
  case steadyField
}
