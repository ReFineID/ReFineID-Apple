// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import XCTest

/// Native UI test for document signing across macOS and iOS.
///
/// - macOS: Drags a document from Desktop into the app's drop area,
///   triggers the signature, handles the save dialog, and verifies the output.
/// - iOS: Waits for the incoming remote signing authorization prompt,
///   types PIN 2, and approves the signature.
@MainActor
internal final class DocumentSigningUITests: XCTestCase {
  // MARK: Static Properties

  private static let targetFileName = "Nimetön.pdf"
  private static let signTimeout: TimeInterval = 90

  // MARK: macOS Tests

  #if os(macOS)

    /// Drags or seeds the target document from the Desktop into ReFineID, triggers
    /// the signing operation, and completes the save dialog.
    internal func testDragDocumentFromDesktopAndSign() throws {
      let desktopDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
      let targetURL = desktopDir.appendingPathComponent(Self.targetFileName)
      let outputURL = desktopDir.appendingPathComponent("Nimetön-signed.pdf")

      guard FileManager.default.fileExists(atPath: targetURL.path) else {
        throw XCTSkip("Test target file not found on Desktop: \(targetURL.path)")
      }

      try? FileManager.default.removeItem(at: outputURL)

      let app = UITestApp.launch(arguments: [
        "--seed-document", targetURL.path,
        "--unattended-sign-destination", outputURL.path,
      ])
      let statusWindow = app.windows["status"]
      XCTAssertTrue(statusWindow.waitForExistence(timeout: 10), "Status window not found")

      let dropArea = statusWindow.descendants(matching: .any)[UITestIdentifiers.documentDropArea]
        .firstMatch
      XCTAssertTrue(dropArea.waitForExistence(timeout: 10), "Drop target not found")

      let queuedDoc = statusWindow.staticTexts.matching(
        NSPredicate(format: "label CONTAINS[c] 'Nimet' OR value CONTAINS[c] 'Nimet'")
      ).firstMatch
      XCTAssertTrue(queuedDoc.waitForExistence(timeout: 5), "Document not in signing pile")

      let signButton = statusWindow.buttons["signDocument"]
      XCTAssertTrue(signButton.waitForExistence(timeout: 10), "Sign button not available")
      waitForSignButton(signButton)
      signButton.click()

      waitForOutputFile(outputURL)
      attachScreenshot(app.screenshot(), named: "signing-outcome")
    }

    private func waitForSignButton(_ button: XCUIElement) {
      let deadline = Date().addingTimeInterval(15)
      while Date() < deadline, !button.isEnabled {
        Thread.sleep(forTimeInterval: 0.5)
      }
      XCTAssertTrue(button.isEnabled, "Sign button is disabled")
    }

    private func waitForOutputFile(_ url: URL) {
      let deadline = Date().addingTimeInterval(Self.signTimeout)
      while Date() < deadline, !FileManager.default.fileExists(atPath: url.path) {
        Thread.sleep(forTimeInterval: 0.5)
      }
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: url.path),
        "Document signing did not complete within timeout"
      )
    }

  #endif

  // MARK: iOS Tests

  #if os(iOS)

    /// Waits for an incoming remote signing authorization request, enters PIN 2,
    /// and taps OK to authorize.
    internal func testApproveSigningRequestWithPin2() throws {
      guard let pin2Digits = UITestEnvironment.pin2 else {
        throw XCTSkip("REFINEID_TEST_PIN2 environment variable is required")
      }
      let app = XCUIApplication()
      app.launch()

      let interruptionToken = addUIInterruptionMonitor(withDescription: "Near-Field Sheet") { _ in
        // Never synthesize a dismissal for system alerts/sheets during near-field operations
        true
      }
      defer {
        removeUIInterruptionMonitor(interruptionToken)
      }

      let alert = app.alerts.firstMatch
      XCTAssertTrue(
        alert.waitForExistence(timeout: Self.signTimeout),
        "Signing authorization alert did not appear within timeout"
      )

      let pinField = alert.secureTextFields.firstMatch
      XCTAssertTrue(pinField.waitForExistence(timeout: 5), "PIN 2 field in alert not found")
      pinField.tap()
      pinField.typeText(pin2Digits)

      let okButton = alert.buttons["OK"].firstMatch
      XCTAssertTrue(okButton.waitForExistence(timeout: 5), "OK button missing in alert")
      let deadline = Date().addingTimeInterval(5)
      while Date() < deadline, !okButton.isEnabled {
        Thread.sleep(forTimeInterval: 0.2)
      }
      XCTAssertTrue(okButton.isEnabled, "OK button is not enabled with entered PIN 2")
      okButton.tap()

      // Keep runner alive so app process is not terminated during card crypto execution
      Thread.sleep(forTimeInterval: 35)

      attachScreenshot(app.screenshot(), named: "signing-approved-on-device")
    }

  #endif
}
