//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation
import ObjectiveC.runtime
import os.log

protocol NightShiftControlling: AnyObject {
  var available: Bool { get }
  func refreshStrength() -> Float?
  func isNightShiftEnabled() -> Bool?
  @discardableResult func setStrength(_ strength: Float, commit: Bool) -> Bool
}

protocol NightShiftRuntime {
  var hasClientClass: Bool { get }
  var hasRequiredSelectors: Bool { get }
  func supportsBlueLightReduction() -> Bool
  func getStrength() -> Float?
  func isNightShiftEnabled() -> Bool?
  func setStrength(_ strength: Float, commit: Bool) -> Bool
}

private struct BlueLightTime {
  var hour: Int32 = 0
  var minute: Int32 = 0
}

private struct BlueLightSchedule {
  var fromTime = BlueLightTime()
  var toTime = BlueLightTime()
}

private struct BlueLightStatus {
  var active = false
  var enabled = false
  var sunSchedulePermitted = false
  var mode: Int32 = 0
  var schedule = BlueLightSchedule()
  var disableFlags: UInt64 = 0
  var unknown = false
}

private final class CoreBrightnessNightShiftRuntime: NightShiftRuntime {
  private let clientClass: CBBlueLightClient.Type?
  private var client: CBBlueLightClient?

  init(classLookup: (String) -> AnyClass? = NSClassFromString) {
    guard let candidate = classLookup("CBBlueLightClient") else {
      self.clientClass = nil
      return
    }
    self.clientClass = candidate as? CBBlueLightClient.Type
  }

  var hasClientClass: Bool {
    self.clientClass != nil
  }

  var hasRequiredSelectors: Bool {
    guard let clientClass = self.clientClass else {
      return false
    }
    return class_getClassMethod(clientClass, #selector(CBBlueLightClient.supportsBlueLightReduction)) != nil
      && class_getInstanceMethod(clientClass, #selector(CBBlueLightClient.getStrength(_:))) != nil
      && class_getInstanceMethod(clientClass, #selector(CBBlueLightClient.setStrength(_:commit:))) != nil
  }

  func supportsBlueLightReduction() -> Bool {
    guard self.hasRequiredSelectors, let clientClass = self.clientClass, clientClass.supportsBlueLightReduction() else {
      return false
    }
    self.client = clientClass.init()
    return self.client != nil
  }

  func getStrength() -> Float? {
    guard let client = self.client else {
      return nil
    }
    var strength: Float = 0
    return client.getStrength(&strength) ? strength : nil
  }

  func isNightShiftEnabled() -> Bool? {
    guard let client = self.client else {
      return nil
    }
    let selector = NSSelectorFromString("getBlueLightStatus:")
    guard let method = class_getInstanceMethod(type(of: client), selector) else {
      return nil
    }
    typealias GetBlueLightStatus = @convention(c) (UnsafeRawPointer, Selector, UnsafeMutableRawPointer) -> Bool
    let getBlueLightStatus = unsafeBitCast(method_getImplementation(method), to: GetBlueLightStatus.self)
    var status = BlueLightStatus()
    let didReadStatus = withUnsafeMutablePointer(to: &status) { statusPointer in
      getBlueLightStatus(Unmanaged.passUnretained(client).toOpaque(), selector, UnsafeMutableRawPointer(statusPointer))
    }
    return didReadStatus ? status.enabled : nil
  }

  func setStrength(_ strength: Float, commit: Bool) -> Bool {
    guard let client = self.client else {
      return false
    }
    return client.setStrength(strength, commit: commit)
  }
}

final class NightShiftController: NightShiftControlling {
  static let shared = NightShiftController()

  private let runtime: NightShiftRuntime
  private var didLogFailure = false
  private(set) var available: Bool

  init(runtime: NightShiftRuntime = CoreBrightnessNightShiftRuntime()) {
    self.runtime = runtime
    self.available = false
    guard runtime.hasClientClass else {
      self.logFailure("CBBlueLightClient class is unavailable")
      return
    }
    guard runtime.hasRequiredSelectors else {
      self.logFailure("CBBlueLightClient is missing a required selector")
      return
    }
    guard runtime.supportsBlueLightReduction() else {
      self.logFailure("Night Shift is unsupported or could not be initialized")
      return
    }
    self.available = true
  }

  func refreshStrength() -> Float? {
    guard self.available, let strength = self.runtime.getStrength() else {
      self.markUnavailable("Night Shift strength read failed")
      return nil
    }
    return max(0, min(1, strength))
  }

  func isNightShiftEnabled() -> Bool? {
    guard self.available else {
      return nil
    }
    return self.runtime.isNightShiftEnabled()
  }

  @discardableResult func setStrength(_ strength: Float, commit: Bool) -> Bool {
    guard self.available, self.runtime.setStrength(max(0, min(1, strength)), commit: commit) else {
      self.markUnavailable("Night Shift strength write failed")
      return false
    }
    return true
  }

  private func markUnavailable(_ message: String) {
    self.available = false
    self.logFailure(message)
  }

  private func logFailure(_ message: String) {
    guard !self.didLogFailure else {
      return
    }
    self.didLogFailure = true
    os_log("Night Shift unavailable: %{public}@", type: .error, message)
  }
}
