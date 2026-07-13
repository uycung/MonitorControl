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

  func testMenuEligibilityDependsOnlyOnPreferenceAndAvailability() {
    for preferenceEnabled in [false, true] {
      for available in [false, true] {
        for _ in 0 ... 2 {
          XCTAssertEqual(MenuHandler.shouldShowNightShift(preferenceEnabled: preferenceEnabled, nightShiftAvailable: available), preferenceEnabled && available)
        }
      }
    }
  }
}

private final class FakeNightShiftRuntime: NightShiftRuntime {
  let hasClientClass: Bool
  let hasRequiredSelectors: Bool
  var strength: Float?
  private(set) var supportsCallCount = 0
  private(set) var getStrengthCallCount = 0
  private(set) var setStrengthCalls: [(strength: Float, commit: Bool)] = []
  private(set) var setModeCallCount = 0
  private(set) var setEnabledCallCount = 0
  private(set) var getBlueLightStatusCallCount = 0

  init(hasClientClass: Bool = true, hasRequiredSelectors: Bool = true, strength: Float? = 0.5) {
    self.hasClientClass = hasClientClass
    self.hasRequiredSelectors = hasRequiredSelectors
    self.strength = strength
  }

  func supportsBlueLightReduction() -> Bool {
    self.supportsCallCount += 1
    return true
  }

  func getStrength() -> Float? {
    self.getStrengthCallCount += 1
    return self.strength
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

  func getBlueLightStatus() {
    self.getBlueLightStatusCallCount += 1
  }
}
