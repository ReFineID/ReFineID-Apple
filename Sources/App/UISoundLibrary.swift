// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import AudioToolbox
  import Foundation

  /// The system's own interface sounds, by the name of the file iOS
  /// keeps them in.
  ///
  /// The numbered `SystemSoundID` constants reach only a fraction of
  /// what the system actually has, and none of the NFC family: the tones
  /// a holder already associates with a card being read live in
  /// `/System/Library/Audio/UISounds` as named files. Registering one by
  /// URL gives back an ordinary sound id, so a card operation can sound
  /// the way every other card operation on the phone does rather than
  /// borrowing an unrelated beep.
  ///
  /// The directory is not API. A name that is not there on some future
  /// system resolves to the numbered tone the caller passes as its
  /// fallback, so a missing file costs the right sound and never the
  /// feedback itself.
  ///
  /// Ids are registered once and kept: `AudioServicesCreateSystemSoundID`
  /// allocates, and re-registering per play would leak one allocation per
  /// sound played.
  @MainActor
  internal enum UISoundLibrary {
    /// Where iOS keeps its interface sounds.
    private static let directory = "/System/Library/Audio/UISounds/"

    /// The container every one of them is in.
    private static let fileExtension = "caf"

    /// Ids already registered this launch, by file name.
    private static var registered: [String: SystemSoundID] = [:]

    /// The sound id for `name`, or `fallback` when this system has no
    /// such file.
    internal static func soundID(named name: String, fallback: SystemSoundID) -> SystemSoundID {
      if let known = Self.registered[name] {
        return known
      }
      let url = URL(fileURLWithPath: Self.directory + name + "." + Self.fileExtension)
      guard FileManager.default.fileExists(atPath: url.path) else {
        Self.registered[name] = fallback
        return fallback
      }
      var created: SystemSoundID = 0
      guard AudioServicesCreateSystemSoundID(url as CFURL, &created) == kAudioServicesNoError else {
        Self.registered[name] = fallback
        return fallback
      }
      Self.registered[name] = created
      return created
    }
  }

#endif
