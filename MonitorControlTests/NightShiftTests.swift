@testable import MonitorControl
import XCTest

final class NightShiftTests: XCTestCase {
  func testUnavailableRuntimeDoesNotInvokePrivateMethods() {
    let runtime = FakeNightShiftRuntime(hasClientClass: false)
    let controller = NightShiftController(runtime: runtime)

    XCTAssertFalse(controller.available)
    XCTAssertNil(controller.refreshStrength())
    XCTAssertFalse(controller.setStrength(0.5, commit: true))
    XCTAssertEqual(runtime.supportsCallCount, 0)
    XCTAssertEqual(runtime.getStrengthCallCount, 0)
    XCTAssertEqual(runtime.setStrengthCalls.count, 0)
  }

  func testMissingSelectorDoesNotInvokePrivateMethods() {
    let runtime = FakeNightShiftRuntime(hasRequiredSelectors: false)
    let controller = NightShiftController(runtime: runtime)

    XCTAssertFalse(controller.available)
    XCTAssertEqual(runtime.supportsCallCount, 0)
    XCTAssertEqual(runtime.getStrengthCallCount, 0)
    XCTAssertEqual(runtime.setStrengthCalls.count, 0)
  }

  func testSliderUsesExpectedCommitFlagsAndInitialStrength() {
    let runtime = FakeNightShiftRuntime(strength: 0.37)
    let controller = NightShiftController(runtime: runtime)
    let handler = NightShiftSliderHandler(nightShiftController: controller)
    guard let slider = handler.slider, let cell = slider.cell as? SliderHandler.MCSliderCell else {
      return XCTFail("Night Shift slider was not created")
    }

    XCTAssertEqual(slider.floatValue, 0.37, accuracy: 0.001)
    XCTAssertEqual(runtime.getStrengthCallCount, 1)

    cell.isTracking = true
    slider.floatValue = 0.55
    handler.valueChanged(slider: slider)
    XCTAssertEqual(runtime.setStrengthCalls.last?.commit, false)

    slider.trackingEnded?()
    XCTAssertEqual(runtime.setStrengthCalls.last?.commit, true)

    cell.isTracking = false
    slider.floatValue = 0.75
    handler.valueChanged(slider: slider)
    XCTAssertEqual(runtime.setStrengthCalls.last?.commit, true)
  }

  func testInfoIconUsesInstantTrackingOverlayInsteadOfSystemTooltip() {
    let presenter = FakeNightShiftOverlayPresenter()
    let icon = NightShiftInfoIconView(frame: NSRect(x: 0, y: 0, width: 15, height: 15), message: NightShiftSliderHandler.infoMessage, overlayPresenter: presenter)

    XCTAssertNil(icon.toolTip)
    XCTAssertTrue(icon.trackingAreas.contains { trackingArea in
      trackingArea.options.contains(.mouseEnteredAndExited)
        && trackingArea.options.contains(.activeAlways)
        && trackingArea.options.contains(.inVisibleRect)
    })

    icon.showHoverOverlay()
    XCTAssertEqual(presenter.messages, [NightShiftSliderHandler.infoMessage])
    icon.hideHoverOverlay()
    XCTAssertEqual(presenter.hideCallCount, 1)
  }

  func testDisabledNightShiftShowsMessageAtRealDragStart() {
    let runtime = FakeNightShiftRuntime(nightShiftEnabled: false)
    let presenter = FakeNightShiftOverlayPresenter()
    let handler = NightShiftSliderHandler(nightShiftController: NightShiftController(runtime: runtime), warningOverlayPresenter: presenter)
    guard let slider = handler.slider, let cell = slider.cell as? NightShiftSliderHandler.TrackingSliderCell else {
      return XCTFail("Night Shift tracking cell was not installed")
    }

    cell.notifyTrackingStarted()

    XCTAssertEqual(runtime.getBlueLightStatusCallCount, 1)
    XCTAssertEqual(presenter.messages, [NightShiftSliderHandler.disabledMessage])
    XCTAssertTrue(slider.isTracking == false)
  }

  func testEnabledNightShiftDoesNotShowMessageAtRealDragStart() {
    let runtime = FakeNightShiftRuntime(nightShiftEnabled: true)
    let presenter = FakeNightShiftOverlayPresenter()
    let handler = NightShiftSliderHandler(nightShiftController: NightShiftController(runtime: runtime), warningOverlayPresenter: presenter)
    guard let cell = handler.slider?.cell as? NightShiftSliderHandler.TrackingSliderCell else {
      return XCTFail("Night Shift tracking cell was not installed")
    }

    cell.notifyTrackingStarted()

    XCTAssertEqual(runtime.getBlueLightStatusCallCount, 1)
    XCTAssertTrue(presenter.messages.isEmpty)
  }

  func testDisabledMessageDecision() {
    XCTAssertTrue(NightShiftSliderHandler.shouldShowDisabledMessage(nightShiftEnabled: false))
    XCTAssertFalse(NightShiftSliderHandler.shouldShowDisabledMessage(nightShiftEnabled: true))
  }

  func testSchedulePreservationFacadeOnlyUsesPermittedRuntimeSurface() {
    let runtime = FakeNightShiftRuntime(strength: 0.25)
    let controller = NightShiftController(runtime: runtime)

    XCTAssertTrue(controller.available)
    XCTAssertEqual(controller.refreshStrength(), 0.25)
    XCTAssertTrue(controller.setStrength(0.8, commit: true))
    XCTAssertEqual(runtime.setModeCallCount, 0)
    XCTAssertEqual(runtime.setEnabledCallCount, 0)
    XCTAssertEqual(runtime.getBlueLightStatusCallCount, 0)
  }

  func testNoBuiltInDisplayPresentReturnsFalse() {
    XCTAssertFalse(MenuHandler.hasBuiltInDisplay([.other]))
  }

  func testBuiltInDisplayPresentReturnsTrue() {
    XCTAssertTrue(MenuHandler.hasBuiltInDisplay([.builtIn]))
  }

  func testMixedDisplayListReturnsTrue() {
    XCTAssertTrue(MenuHandler.hasBuiltInDisplay([.other, .builtIn, .other]))
  }

  func testMenuEligibilityDependsOnPreferenceAvailabilityAndBuiltInDisplay() {
    for preferenceEnabled in [false, true] {
      for available in [false, true] {
        for builtInDisplayPresent in [false, true] {
          XCTAssertEqual(
            MenuHandler.shouldShowNightShift(
              preferenceEnabled: preferenceEnabled,
              nightShiftAvailable: available,
              builtInDisplayPresent: builtInDisplayPresent
            ),
            preferenceEnabled && available && builtInDisplayPresent
          )
        }
      }
    }
  }

  func testSingleDisplayWithoutBoxesKeepsNightShiftAtTopLevel() {
    XCTAssertEqual(MenuHandler.nightShiftPlacement(boxesRendered: false), .topLevel)
  }

  func testMultipleDisplaysWithBoxesPlacesNightShiftInsideBuiltInDisplayBlock() {
    XCTAssertEqual(MenuHandler.nightShiftPlacement(boxesRendered: true), .builtInDisplayBlock)
  }
}

private final class FakeNightShiftRuntime: NightShiftRuntime {
  let hasClientClass: Bool
  let hasRequiredSelectors: Bool
  var strength: Float?
  var nightShiftEnabled: Bool?
  private(set) var supportsCallCount = 0
  private(set) var getStrengthCallCount = 0
  private(set) var setStrengthCalls: [(strength: Float, commit: Bool)] = []
  private(set) var setModeCallCount = 0
  private(set) var setEnabledCallCount = 0
  private(set) var getBlueLightStatusCallCount = 0

  init(hasClientClass: Bool = true, hasRequiredSelectors: Bool = true, strength: Float? = 0.5, nightShiftEnabled: Bool? = true) {
    self.hasClientClass = hasClientClass
    self.hasRequiredSelectors = hasRequiredSelectors
    self.strength = strength
    self.nightShiftEnabled = nightShiftEnabled
  }

  func supportsBlueLightReduction() -> Bool {
    self.supportsCallCount += 1
    return true
  }

  func getStrength() -> Float? {
    self.getStrengthCallCount += 1
    return self.strength
  }

  func isNightShiftEnabled() -> Bool? {
    self.getBlueLightStatusCallCount += 1
    return self.nightShiftEnabled
  }

  func setStrength(_ strength: Float, commit: Bool) -> Bool {
    self.setStrengthCalls.append((strength, commit))
    self.strength = strength
    return true
  }

  func setMode() {
    self.setModeCallCount += 1
  }

  func setEnabled() {
    self.setEnabledCallCount += 1
  }
}

private final class FakeNightShiftOverlayPresenter: NightShiftOverlayPresenting {
  private(set) var messages: [String] = []
  private(set) var hideCallCount = 0

  func show(message: String, relativeTo _: NSView) {
    self.messages.append(message)
  }

  func hide() {
    self.hideCallCount += 1
  }
}
