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
/// A refused SCS transaction step, as the specification's reason pair.
///
/// The code follows the same classes as the JSON `/sign` path:
/// 400 malformed, 401 credential, 403 policy, 500 internal, 501
/// unimplemented (DVV SCS specification v1.3 §2.6.3).
public struct ScsTransactionError: Error, Equatable, Sendable {
  /// The specification reason code.
  public let code: Int

  /// The human-readable reason.
  public let message: String

  /// A malformed-request refusal.
  public static func badRequest(_ message: String) -> Self {
    Self(code: ScsValues.reasonBadRequest, message: message)
  }

  /// A policy refusal.
  public static func forbidden(_ message: String) -> Self {
    Self(code: ScsValues.reasonForbidden, message: message)
  }

  /// An internal failure.
  public static func internalError(_ message: String) -> Self {
    Self(code: ScsValues.reasonInternalError, message: message)
  }

  /// A valid request for an unimplemented capability.
  public static func notImplemented(_ message: String) -> Self {
    Self(code: ScsValues.reasonNotImplemented, message: message)
  }

  /// Wraps a signing-backend refusal in its specification reason
  /// pair; anything else is an internal failure.
  internal static func wrapping(_ error: any Error) -> Self {
    guard let failure = error as? ScsBackendFailure else {
      return .internalError("\(error)")
    }
    return Self(code: failure.reasonCode, message: failure.reasonText)
  }
}
