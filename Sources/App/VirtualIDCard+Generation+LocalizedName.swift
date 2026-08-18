#if os(iOS)

  import CardCore

  extension VirtualIDCard.Generation {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.generationName(self)
    }
  }

#endif
