// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import SwiftUI

extension View {
  /// Runs an action when a value changes, on every platform this app
  /// supports.
  ///
  /// The two-parameter `onChange` arrived in iOS 17 and macOS 14, and the
  /// single-parameter one it replaced is deprecated there. A device running
  /// iOS 16 needs the older spelling, and a Mac built against a current SDK
  /// refuses it as deprecated, so neither can be written directly in a file
  /// both platforms compile. This chooses between them once.
  @ViewBuilder
  internal func onValueChange<Value: Equatable>(
    of value: Value,
    perform action: @escaping (Value) -> Void
  ) -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      onChange(of: value) { _, updated in action(updated) }
    } else {
      deprecatedOnChange(of: value, perform: action)
    }
  }

  /// The pre-iOS 17 spelling, isolated so its deprecation stays here.
  ///
  /// A deprecated call made from an equally deprecated context is not
  /// reported, which is what keeps the Mac build free of the warning it
  /// treats as an error.
  @available(iOS, deprecated: 17.0)
  @available(macOS, deprecated: 14.0)
  private func deprecatedOnChange<Value: Equatable>(
    of value: Value,
    perform action: @escaping (Value) -> Void
  ) -> some View {
    onChange(of: value, perform: action)
  }
}
