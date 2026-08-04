import Foundation

/// The holder's handwritten signature, as the travel-document
/// application stores it (ICAO 9303-10, data group 7).
///
/// DG7 is a template holding a count and that many images. The count
/// is read rather than assumed: the encoding permits several, a
/// Finnish card carries one, and a reader that took the first without
/// looking would be right by luck.
public enum DisplayedSignature {
  /// What a data group said, when it did not say an image.
  public enum Failure: Error, Equatable, Sendable {
    /// The template holds no image.
    case noImage

    /// The bytes are not a DG7 template.
    case notADataGroup

    /// The image is in an encoding this does not carry into a
    /// document.
    case unsupportedImageFormat
  }

  /// An image and what it is encoded as.
  public struct Image: Equatable, Sendable {
    /// The encoded image bytes, exactly as the card stores them.
    public let bytes: Data

    /// Whether those bytes are JPEG, which embeds into a PDF
    /// unchanged.
    public let isJpeg: Bool
  }

  /// Bytes in the image's two-byte tag.
  private static let imageTagLength = 2

  /// Bytes in an ordinary one-byte tag.
  private static let plainTagLength = 1

  /// The bytes a JPEG opens with, JFIF and Exif alike: the
  /// start-of-image marker followed by the first segment's own.
  private static let jpegMarker: [UInt8] = [
    ImageValues.markerIntroducer,
    ImageValues.startOfImage,
    ImageValues.markerIntroducer,
  ]

  /// The image out of a DG7 template.
  ///
  /// JPEG is the format that matters: a PDF embeds it verbatim, with
  /// no decoding and no re-encoding. JPEG 2000 is permitted by the
  /// specification and is refused here rather than half-supported -
  /// PDF can carry it, but not every reader draws it, and a signature
  /// that renders on one machine and not another is worse than none.
  ///
  /// The walk is written out rather than handed to `DerReader`
  /// because the image is tagged `5F 43`, the high-tag-number form:
  /// a reader that takes one byte as the tag would read `43` as the
  /// length and parse nonsense confidently.
  public static func image(inDataGroup group: Data) throws -> Image {
    let bytes = Array(group)
    guard
      bytes.first == FineidValues.displayedSignatureTag,
      let template = Self.contentRange(in: bytes, from: Self.plainTagLength)
    else {
      throw Failure.notADataGroup
    }
    guard
      let count = Self.instanceCount(in: bytes, within: template),
      count > 0
    else {
      throw Failure.notADataGroup
    }
    guard let image = Self.imageRange(in: bytes, within: template) else {
      throw Failure.noImage
    }
    let encoded = Data(bytes[image])
    guard Self.isJpeg(encoded) else {
      throw Failure.unsupportedImageFormat
    }
    return Image(bytes: encoded, isJpeg: true)
  }

  /// How many images the template says it holds.
  private static func instanceCount(
    in bytes: [UInt8],
    within template: Range<Int>
  ) -> Int? {
    guard
      template.lowerBound < bytes.count,
      bytes[template.lowerBound] == DerValues.tagInteger,
      let value = Self.contentRange(
        in: bytes, from: template.lowerBound + Self.plainTagLength
      ),
      value.count == Self.plainTagLength
    else {
      return nil
    }
    return Int(bytes[value.lowerBound])
  }

  /// Where the image sits inside the template, found by its two-byte
  /// tag rather than by position.
  private static func imageRange(
    in bytes: [UInt8],
    within template: Range<Int>
  ) -> Range<Int>? {
    var cursor = template.lowerBound
    while cursor + 1 < template.upperBound {
      let isImage =
        bytes[cursor] == FineidValues.biometricTemplateTag
        && bytes[cursor + 1] == FineidValues.biometricImageTag
      let headerLength = isImage ? Self.imageTagLength : Self.plainTagLength
      guard
        let content = Self.contentRange(
          in: bytes, from: cursor + headerLength
        )
      else {
        return nil
      }
      if isImage { return content }
      cursor = content.upperBound
    }
    return nil
  }

  /// The content of one element whose length octets start at
  /// `offset`, or nil when the length overruns what is there.
  private static func contentRange(
    in bytes: [UInt8],
    from offset: Int
  ) -> Range<Int>? {
    guard offset < bytes.count else { return nil }
    let first = bytes[offset]
    var start = offset + 1
    var length = Int(first)
    if first & DerValues.longFormMask != 0 {
      let octets = Int(first & DerValues.longFormCountMask)
      guard octets > 0, start + octets <= bytes.count else { return nil }
      length = 0
      for index in start..<(start + octets) {
        length = length << UInt8.bitWidth | Int(bytes[index])
      }
      start += octets
    }
    guard start + length <= bytes.count else { return nil }
    return start..<(start + length)
  }

  /// Whether the bytes open as JFIF or Exif JPEG.
  private static func isJpeg(_ bytes: Data) -> Bool {
    guard bytes.count > Self.jpegMarker.count else { return false }
    return Array(bytes.prefix(Self.jpegMarker.count)) == Self.jpegMarker
  }
}
