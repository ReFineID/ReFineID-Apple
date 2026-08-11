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
/// What the PIN container says about the PIN having been changed since
/// manufacture (the DF 2F object, S1 v4.2 §3.15.3).
public enum PinChangeRecord: Equatable, Sendable {
  /// Changed at least once: under the preset-PIN scheme, activation
  /// has happened.
  case changed

  /// Never changed: the factory state under the preset-PIN scheme.
  case unchanged

  /// Absent or carrying an unknown flag value; no decision may rest
  /// on it.
  case unreadable
}
