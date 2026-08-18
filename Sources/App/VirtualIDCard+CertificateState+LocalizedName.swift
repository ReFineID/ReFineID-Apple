#if os(iOS)

  import CardCore

  internal extension VirtualIDCard.CertificateState {
    fileprivate var localizedName: String {
      VirtualIDCardOverlayLocalization.certificateStateName(self)
    }
  }

#endif
