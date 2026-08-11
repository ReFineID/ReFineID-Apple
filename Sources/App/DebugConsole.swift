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
#if DEBUG

  import Darwin
  import Foundation

  /// Where a cable-side debug mode writes, and how it ends.
  ///
  /// `xcrun devicectl device process launch --console` captures this
  /// process's stdout and nothing else about the run, so stdout is the
  /// whole instrument. Every line is flushed as it is produced rather than
  /// at exit, because the modes that touch a card block on a system sheet:
  /// a buffered run would hide exactly where it stalled, which is the one
  /// thing the run was started to find out.
  ///
  /// DEBUG only. A release build has no launch mode to write here.
  internal enum DebugConsole {
    /// Prints one line and flushes it.
    internal static func emit(_ line: String) {
      print(line)
      fflush(stdout)
    }

    /// Prints several lines and flushes them.
    internal static func emit(_ lines: [String]) {
      for line in lines {
        print(line)
      }
      fflush(stdout)
    }

    /// Ends the run with the status a driving script reads.
    ///
    /// A mode that did not achieve what it was asked for exits non-zero, so
    /// a shell loop can tell a failed measurement from a finished one
    /// without parsing the text above it.
    internal static func finish(succeeded: Bool) -> Never {
      fflush(stdout)
      exit(succeeded ? EXIT_SUCCESS : EXIT_FAILURE)
    }
  }

#endif
