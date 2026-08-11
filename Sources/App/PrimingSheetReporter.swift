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
#if canImport(CoreNFC) && os(iOS)

  import Foundation

  /// Keeps the running step states and repaints the NFC sheet from them.
  ///
  /// Every step change and every sentence go through here, so the sheet
  /// always shows the whole meter rather than whichever half was written
  /// most recently. The card work runs on its own queue and the steps
  /// are reported from there, so the states live behind a lock.
  ///
  /// `@unchecked Sendable` is the audit: the dictionary is touched only
  /// under the lock, and the session it draws into is itself safe to
  /// update from any thread.
  @available(iOS 26.0, *)
  internal final class PrimingSheetReporter: @unchecked Sendable {
    /// The hold this meter is drawn on, so a caller needing the card
    /// does not have to be handed the session separately.
    internal let session: NearFieldCardSession

    private let lock = NSLock()
    private var states: [CardPrimingStep: CardPrimingStep.State] = [:]

    internal init(session: NearFieldCardSession) {
      self.session = session
    }

    /// Records a step's state and repaints the meter.
    internal func report(_ step: CardPrimingStep, _ state: CardPrimingStep.State) {
      lock.lock()
      states[step] = state
      let snapshot = states
      lock.unlock()
      session.update(message: PrimingSheetMessage.meter(states: snapshot))
    }

    /// Replaces the whole message with why the hold stopped.
    ///
    /// The meter goes when this is called, and deliberately: the panel
    /// truncates anything past its line, so a meter and a reason
    /// together cost the reason. A hold that is about to dismiss has one
    /// thing left to say and it is not how far it got.
    internal func fail(_ sentence: String) {
      session.update(message: sentence)
    }
  }

#endif
