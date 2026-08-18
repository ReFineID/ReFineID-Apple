#if os(iOS)

  import CardCore

  internal extension VirtualIDCard.FaultPreset {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.faultPresetName(self)
    }
  }

#endif
