// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import XCTest

  /// Hardware-free journeys configured through the visible Virtual ID Card.
  @MainActor
  internal final class VirtualIDCardUITests: XCTestCase {
    private enum Destination {
      case cardAccessNumber
      case activation
      case readerIdentity
      case registeredIdentity
    }

    private struct ScenarioCase {
      let name: String
      let destination: Destination
    }

    private struct CredentialJourney {
      let task: String
      let fields: [(identifier: String, value: String)]
      let action: String
      let outcome: String
    }

    private static let appearTimeout: TimeInterval = 10

    override internal func setUp() {
      super.setUp()
      continueAfterFailure = false
    }

    internal func testEveryScenarioIsConfiguredAndRoutedThroughGUI() {
      let cases = [
        ScenarioCase(name: "factory-fresh-nfc", destination: .cardAccessNumber),
        ScenarioCase(
          name: "legacy-factory-fresh-nfc",
          destination: .cardAccessNumber),
        ScenarioCase(
          name: "partial-activation-nfc",
          destination: .cardAccessNumber),
        ScenarioCase(name: "activated-nfc", destination: .cardAccessNumber),
        ScenarioCase(name: "registered-nfc", destination: .registeredIdentity),
        ScenarioCase(name: "factory-fresh-reader", destination: .activation),
        ScenarioCase(name: "activated-reader", destination: .readerIdentity),
        ScenarioCase(name: "pin1-recovery-reader", destination: .readerIdentity),
        ScenarioCase(name: "pin2-recovery-reader", destination: .readerIdentity),
        ScenarioCase(
          name: "puk-recovery-refused-reader",
          destination: .readerIdentity),
        ScenarioCase(name: "absent", destination: .cardAccessNumber),
      ]

      for testCase in cases {
        let app = UITestApp.launchVirtualCard()
        applyScenario(testCase.name, in: app)
        assertDestination(testCase.destination, scenario: testCase.name, in: app)
        app.terminate()
      }
    }

    internal func testEveryFaultPresetIsConfiguredThroughGUI() {
      let presets = [
        "none",
        "nfcDisconnectBeforeConnection",
        "readerFailsCounterQuery",
        "cardRemovedDuringPINChange",
        "responseLostAfterPIN1Activation",
        "responseLostAfterPIN2Activation",
        "certificateReadFailure",
        "tokenPublicationFailure",
      ]
      let app = UITestApp.launchVirtualCard()

      for preset in presets {
        openEditor(in: app)
        selectMenu(
          identifier: UITestIdentifiers.virtualCardFault,
          option: preset,
          optionIdentifier: "virtualCardFaultOption.\(preset)",
          in: app,
          scrolling: true)
        applyEditor(in: app)
      }
    }

    internal func testVirtualCardEditorPassesAccessibilityAudit() throws {
      let app = UITestApp.launchVirtualCard()
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      XCTAssertTrue(overlay.waitForExistence(timeout: Self.appearTimeout))
      XCTAssertEqual(overlay.label, "Virtual ID Card")
      XCTAssertFalse((overlay.value as? String ?? "").isEmpty)

      openEditor(in: app)
      try app.performAccessibilityAudit()
    }

    internal func testVirtualCardEditorIsLocalizedAndAccessible() {
      for language in ["fi", "sv"] {
        let app = UITestApp.launch(
          language: language,
          arguments: ["--virtual-card", "absent"])
        let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
        XCTAssertTrue(
          overlay.waitForExistence(timeout: Self.appearTimeout),
          "floating Virtual ID Card is missing in \(language)")
        XCTAssertFalse(overlay.label.isEmpty)
        XCTAssertNotEqual(
          overlay.label,
          "Virtual ID Card",
          "Virtual ID Card kept its English accessibility label in \(language)")

        openEditor(in: app)
        let scenario = app.descendants(matching: .any)[
          UITestIdentifiers.virtualCardScenario
        ]
        let fault = app.descendants(matching: .any)[
          UITestIdentifiers.virtualCardFault
        ]
        XCTAssertTrue(scenario.waitForExistence(timeout: Self.appearTimeout))
        XCTAssertFalse(scenario.label.isEmpty)
        XCTAssertFalse(
          scenario.label.localizedCaseInsensitiveContains("Preset"),
          "scenario picker kept its English label in \(language)")

        scrollTo(fault, in: app)
        XCTAssertTrue(fault.waitForExistence(timeout: Self.appearTimeout))
        XCTAssertFalse(fault.label.isEmpty)
        XCTAssertFalse(
          fault.label.localizedCaseInsensitiveContains("Fault"),
          "fault picker kept its English label in \(language)")
        app.terminate()
      }
    }

    internal func testFactoryFreshNFCCardActivatesThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("factory-fresh-nfc", in: app)
      connect(accessNumber: "123456", in: app)

      fillSecure("managementActivationEntry", with: "1234567", in: app)
      fillSecure("managementActivationPin1", with: "4567", in: app)
      fillSecure("managementActivationPin1Repeat", with: "4567", in: app)
      fillSecure("managementActivationPin2", with: "654321", in: app)
      fillSecure("managementActivationPin2Repeat", with: "654321", in: app)
      commit(action: UITestIdentifiers.managementActivate, in: app)

      XCTAssertTrue(
        app.secureTextFields[UITestIdentifiers.pin1Field]
          .waitForExistence(timeout: Self.appearTimeout),
        "successful activation did not reveal authentication")
    }

    internal func testActivatedNFCCardRevealsAuthenticationThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("activated-nfc", in: app)

      connect(accessNumber: "123456", in: app)

      XCTAssertTrue(
        app.secureTextFields[UITestIdentifiers.pin1Field]
          .waitForExistence(timeout: Self.appearTimeout),
        "activated card did not reveal PIN 1 authentication")
    }

    internal func testPartialActivationRequestsOnlyPIN2ThroughGUI() {
      let app = UITestApp.launchVirtualCard()
      applyScenario("partial-activation-nfc", in: app)

      connect(accessNumber: "123456", in: app)

      XCTAssertTrue(
        app.secureTextFields["managementActivationPin2"]
          .waitForExistence(timeout: Self.appearTimeout))
      XCTAssertFalse(app.secureTextFields["managementActivationPin1"].exists)
    }

    internal func testEveryCredentialOperationRunsThroughGUI() {
      let journeys = [
        CredentialJourney(
          task: "Change PIN 1",
          fields: [
            ("managementChangePIN1Current", "1234"),
            ("managementChangePIN1New", "9876"),
            ("managementChangePIN1Repeat", "9876"),
          ],
          action: UITestIdentifiers.managementChangePin1,
          outcome: "PIN 1 changed"),
        CredentialJourney(
          task: "Change PIN 2",
          fields: [
            ("managementChangePIN2Current", "123456"),
            ("managementChangePIN2New", "987654"),
            ("managementChangePIN2Repeat", "987654"),
          ],
          action: UITestIdentifiers.managementChangePin2,
          outcome: "PIN 2 changed"),
        CredentialJourney(
          task: "Reset PIN 1",
          fields: [
            ("managementResetPIN1Puk", "12345678"),
            ("managementResetPIN1New", "9876"),
            ("managementResetPIN1Repeat", "9876"),
          ],
          action: UITestIdentifiers.managementResetPin1,
          outcome: "PIN 1 reset"),
        CredentialJourney(
          task: "Reset PIN 2",
          fields: [
            ("managementResetPIN2Puk", "12345678"),
            ("managementResetPIN2New", "987654"),
            ("managementResetPIN2Repeat", "987654"),
          ],
          action: UITestIdentifiers.managementResetPin2,
          outcome: "PIN 2 reset"),
      ]

      for journey in journeys {
        let app = UITestApp.launchVirtualCard()
        applyScenario("activated-reader", in: app)
        openManagement(in: app)
        selectMenu(
          identifier: UITestIdentifiers.managementTask,
          option: journey.task,
          in: app)
        for field in journey.fields {
          fillSecure(field.identifier, with: field.value, in: app)
        }
        commit(action: journey.action, in: app)
        XCTAssertTrue(
          app.staticTexts[journey.outcome]
            .waitForExistence(timeout: Self.appearTimeout),
          "\(journey.task) did not publish its outcome")
        app.terminate()
      }
    }

    internal func testRetryCounterEditedInGUISelectsRecovery() {
      let app = UITestApp.launchVirtualCard()
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardScenario,
        option: "activated-reader",
        optionIdentifier: "virtualCardScenarioOption.activated-reader",
        in: app)
      let stepper = app.steppers[UITestIdentifiers.virtualCardPIN1Attempts]
      scrollTo(stepper, in: app)
      XCTAssertTrue(stepper.waitForExistence(timeout: Self.appearTimeout))
      let decrement = stepper.buttons.firstMatch
      XCTAssertTrue(decrement.exists)
      decrement.tap()
      decrement.tap()
      decrement.tap()
      applyEditor(in: app)

      openManagement(in: app)

      XCTAssertTrue(
        app.buttons["Reset PIN 1"].firstMatch
          .waitForExistence(timeout: Self.appearTimeout),
        "a PIN 1 retry floor did not select PIN 1 recovery")
    }

    private func assertDestination(
      _ destination: Destination,
      scenario: String,
      in app: XCUIApplication
    ) {
      let element: XCUIElement
      switch destination {
      case .cardAccessNumber:
        element = app.textFields[UITestIdentifiers.cardAccessNumberField]
      case .activation:
        element = app.buttons[UITestIdentifiers.managementActivate]
      case .readerIdentity:
        element = app.staticTexts[UITestIdentifiers.readerCardHolder]
      case .registeredIdentity:
        element = app.staticTexts[UITestIdentifiers.identityStatus]
      }
      XCTAssertTrue(
        element.waitForExistence(timeout: Self.appearTimeout),
        "\(scenario) reached the wrong UI destination")
    }

    private func applyScenario(
      _ scenario: String,
      in app: XCUIApplication
    ) {
      openEditor(in: app)
      selectMenu(
        identifier: UITestIdentifiers.virtualCardScenario,
        option: scenario,
        optionIdentifier: "virtualCardScenarioOption.\(scenario)",
        in: app)
      applyEditor(in: app)
    }

    private func openEditor(in app: XCUIApplication) {
      let overlay = app.buttons[UITestIdentifiers.virtualCardOverlay]
      XCTAssertTrue(
        overlay.waitForExistence(timeout: Self.appearTimeout),
        "floating Virtual ID Card is missing")
      overlay.tap()
      XCTAssertTrue(
        app.descendants(matching: .any)[UITestIdentifiers.virtualCardEditor]
          .waitForExistence(timeout: Self.appearTimeout),
        "Virtual ID Card editor did not open")
    }

    private func applyEditor(in app: XCUIApplication) {
      let apply = app.buttons[UITestIdentifiers.virtualCardApply]
      XCTAssertTrue(apply.waitForExistence(timeout: Self.appearTimeout))
      apply.tap()
      XCTAssertTrue(
        app.buttons[UITestIdentifiers.virtualCardOverlay]
          .waitForExistence(timeout: Self.appearTimeout),
        "Virtual ID Card editor did not close")
    }

    private func selectMenu(
      identifier: String,
      option: String,
      optionIdentifier: String? = nil,
      in app: XCUIApplication,
      scrolling: Bool = false
    ) {
      let menu = app.descendants(matching: .any)[identifier]
      if scrolling {
        scrollTo(menu, in: app)
      }
      XCTAssertTrue(
        menu.waitForExistence(timeout: Self.appearTimeout),
        "\(identifier) menu is missing")
      menu.tap()
      let choice = optionIdentifier.map {
        app.descendants(matching: .any)[$0].firstMatch
      } ?? app.buttons[option].firstMatch
      XCTAssertTrue(
        choice.waitForExistence(timeout: Self.appearTimeout),
        "\(option) menu choice is missing")
      choice.tap()
    }

    private func connect(
      accessNumber: String,
      in app: XCUIApplication
    ) {
      let field = app.textFields[UITestIdentifiers.cardAccessNumberField]
      XCTAssertTrue(field.waitForExistence(timeout: Self.appearTimeout))
      field.tap()
      field.typeText(accessNumber)
      let connect = app.buttons["connectCard"]
      XCTAssertTrue(connect.isEnabled, "Connect is disabled for a complete CAN")
      connect.tap()
    }

    private func openManagement(in app: XCUIApplication) {
      let key = app.buttons["manageCard"]
      XCTAssertTrue(key.waitForExistence(timeout: Self.appearTimeout))
      key.tap()
      XCTAssertTrue(
        app.descendants(matching: .any)[UITestIdentifiers.managementTask]
          .waitForExistence(timeout: Self.appearTimeout))
    }

    private func fillSecure(
      _ identifier: String,
      with value: String,
      in app: XCUIApplication
    ) {
      let field = app.secureTextFields[identifier]
      XCTAssertTrue(
        field.waitForExistence(timeout: Self.appearTimeout),
        "\(identifier) field is missing")
      field.tap()
      field.typeText(value)
    }

    private func commit(action identifier: String, in app: XCUIApplication) {
      let action = app.buttons[identifier]
      scrollTo(action, in: app)
      XCTAssertTrue(action.isEnabled, "\(identifier) is disabled")
      action.tap()
      let confirm = app.buttons
        .matching(identifier: UITestIdentifiers.managementConfirm)
        .firstMatch
      XCTAssertTrue(confirm.waitForExistence(timeout: Self.appearTimeout))
      confirm.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
      for _ in 0..<8 where !element.isHittable {
        app.swipeUp()
      }
    }
  }

#endif
