// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Unpadded base64url alphabet (RFC 4648 section 5).
internal let base64UrlAlphabet = Array(
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

internal func base64UrlEncode(_ bytes: Data) -> String {
  var output: [UInt8] = []
  output.reserveCapacity((bytes.count * 4 + 2) / 3)
  var index = bytes.startIndex
  while index < bytes.endIndex {
    let remaining = bytes.distance(from: index, to: bytes.endIndex)
    let first = bytes[index]
    let second = remaining > 1 ? bytes[bytes.index(index, offsetBy: 1)] : 0
    let third = remaining > 2 ? bytes[bytes.index(index, offsetBy: 2)] : 0
    output.append(base64UrlAlphabet[Int(first >> 2)])
    output.append(base64UrlAlphabet[Int((first & 0x03) << 4 | second >> 4)])
    if remaining > 1 {
      output.append(base64UrlAlphabet[Int((second & 0x0f) << 2 | third >> 6)])
    }
    if remaining > 2 {
      output.append(base64UrlAlphabet[Int(third & 0x3f)])
    }
    index = bytes.index(index, offsetBy: min(3, remaining))
  }
  return String(decoding: output, as: UTF8.self)
}

internal func base64UrlDecode(_ text: String) throws -> Data {
  guard !text.isEmpty, !text.contains("="), text.utf8.count % 4 != 1 else {
    throw PairingOfferError.invalidBase64Url
  }
  let values = try text.utf8.map(decodeBase64UrlByte)
  var output: [UInt8] = []
  output.reserveCapacity(values.count * 3 / 4)
  var index = 0
  while index < values.count {
    let remaining = values.count - index
    let first = values[index]
    let second = values[index + 1]
    output.append(first << 2 | second >> 4)
    if remaining > 2 {
      let third = values[index + 2]
      output.append(second << 4 | third >> 2)
      if remaining > 3 {
        output.append(third << 6 | values[index + 3])
      }
    }
    index += min(4, remaining)
  }
  return Data(output)
}

internal func decodeBase64UrlByte(_ byte: UInt8) throws -> UInt8 {
  switch byte {
  case UInt8(ascii: "A")...UInt8(ascii: "Z"): return byte - UInt8(ascii: "A")
  case UInt8(ascii: "a")...UInt8(ascii: "z"): return byte - UInt8(ascii: "a") + 26
  case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0") + 52
  case UInt8(ascii: "-"): return 62
  case UInt8(ascii: "_"): return 63
  default: throw PairingOfferError.invalidBase64Url
  }
}
