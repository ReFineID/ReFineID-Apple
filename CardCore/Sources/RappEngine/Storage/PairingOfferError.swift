// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Structural or policy failure in a pairing offer.
internal enum PairingOfferError: Error, Equatable {
  case wrongScheme
  case unsupportedVersion
  case wrongType
  case missingField(String)
  case unknownField
  case wrongLength(String)
  case emptyRequiredArray
  case mandatorySuiteMissing
  case tooManyTransports
  case invalidTransport
  case invalidLifetime
  case deadlineOverflow
  case oversized
  case invalidBase64Url
  case wire(WireError)
}
