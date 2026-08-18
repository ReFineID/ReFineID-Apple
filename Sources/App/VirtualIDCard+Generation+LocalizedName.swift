#if os(iOS)

  import CardCore

  extension VirtualIDCard.Generation {
    internal var localizedName: String {
      VirtualIDCardOverlayLocalization.generationName(self)
    }
  }

#endif
