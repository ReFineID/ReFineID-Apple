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

import Foundation

/// How long something took, in the fixed form a trace line carries.
///
/// Timings are the whole reason the trace exists at scale: a contactless
/// signature lives inside a field that lasts about two seconds, so "which
/// exchange spent the field" is a question only elapsed times answer.
/// They are formatted here, once, so two captures can be diffed -- a
/// locale-formatted duration would change shape with the device language
/// and stop comparing.
public enum TraceTiming {
  /// Milliseconds in one second.
  private static let millisecondsPerSecond: Double = 1_000

  /// Attoseconds in one millisecond: `Duration` counts the sub-second
  /// part in attoseconds.
  private static let attosecondsPerMillisecond: Double = 1_000_000_000_000_000

  /// One decimal place, which is finer than a card exchange resolves.
  private static let format: String = "%.1f"

  /// The elapsed time in milliseconds, one decimal place, no unit.
  public static func milliseconds(_ elapsed: Duration) -> String {
    let parts = elapsed.components
    let value =
      Double(parts.seconds) * Self.millisecondsPerSecond
      + Double(parts.attoseconds) / Self.attosecondsPerMillisecond
    return String(format: Self.format, value)
  }
}
