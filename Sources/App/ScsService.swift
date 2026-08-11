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
#if os(macOS)
  import Foundation

  /// The one SCS instance the app runs, started at launch.
  internal enum ScsService {
    /// Created and started exactly once; `static let` gives the
    /// once-semantics.
    private static let server: ScsServer = {
      let created = ScsServer()
      created.start()
      return created
    }()

    /// Starts the localhost SCS if it is not already running.
    internal static func startIfNeeded() {
      _ = Self.server
    }
  }
#endif
