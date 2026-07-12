//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import os.log

/// Slider for VCP 0x14 (select color preset). Unlike brightness or contrast this is not a
/// continuous control: the slider snaps to an ordered list of standard MCCS color preset values
/// and writes the corresponding raw value through the same DDC send path the other sliders use.
class ColorWarmthSliderHandler: SliderHandler {
  private static let writeDebounce: TimeInterval = 0.18

  static let steps: [(name: String, value: UInt16)] = [
    ("sRGB", 0x01),
    (NSLocalizedString("Native", comment: "Color warmth slider step (display native color preset)"), 0x02),
    ("4000K", 0x03),
    ("5000K", 0x04),
    ("6500K", 0x05),
    ("7500K", 0x06),
    ("8200K", 0x07),
    ("9300K", 0x08),
    ("10000K", 0x09),
    ("11500K", 0x0A),
    (NSLocalizedString("User 1", comment: "Color warmth slider step (user color preset)"), 0x0B),
  ]

  static func snap(_ value: Float) -> (normalized: Float, index: Int) {
    let maxIndex = self.steps.count - 1
    let index = max(0, min(maxIndex, Int((value * Float(maxIndex)).rounded())))
    return (Float(index) / Float(maxIndex), index)
  }

  private var lastRequestedIndex: [CGDirectDisplayID: Int] = [:]
  private var lastSentIndex: [CGDirectDisplayID: Int] = [:]
  private var pendingIndex: [CGDirectDisplayID: Int] = [:]
  private var pendingWrite: DispatchWorkItem?
  private var lastWriteTime = Date.distantPast

  override init(display: Display?, command: Command, title: String = "", position: Int = 0) {
    super.init(display: display, command: command, title: title, position: position)
    self.slider?.trackingEnded = { [weak self] in
      self?.commitPendingWrites()
    }
    self.slider?.setNumOfCustomTickmarks(Self.steps.count)
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      self.icon?.image = NSImage(systemSymbolName: "thermometer", accessibilityDescription: title)
    }
  }

  @objc override func valueChanged(slider: MCSlider) {
    let snapped = Self.snap(slider.floatValue)
    slider.floatValue = snapped.normalized
    super.valueChanged(slider: slider)
    self.percentageBox?.stringValue = Self.steps[snapped.index].name
  }

  override func valueChangedOtherDisplay(otherDisplay: OtherDisplay, value: Float) {
    guard !otherDisplay.isSw() else {
      return
    }
    let snapped = Self.snap(value)
    guard self.lastRequestedIndex[otherDisplay.identifier] != snapped.index else {
      return
    }
    self.lastRequestedIndex[otherDisplay.identifier] = snapped.index
    self.pendingIndex[otherDisplay.identifier] = snapped.index
    otherDisplay.savePref(snapped.normalized, for: .selectColorPreset)
    self.schedulePendingWrite(displayID: otherDisplay.identifier, stepIndex: snapped.index)
  }

  override func setValue(_ value: Float, displayID: CGDirectDisplayID = 0) {
    let snapped = Self.snap(value)
    if displayID != 0 {
      self.lastRequestedIndex[displayID] = snapped.index
      self.lastSentIndex[displayID] = snapped.index
    }
    super.setValue(snapped.normalized, displayID: displayID)
    self.percentageBox?.stringValue = Self.steps[snapped.index].name
  }

  private func schedulePendingWrite(displayID: CGDirectDisplayID, stepIndex: Int) {
    self.pendingWrite?.cancel()
    let elapsed = Date().timeIntervalSince(self.lastWriteTime)
    if elapsed >= Self.writeDebounce {
      self.commitPendingWrites()
      return
    }
    os_log("Color Warmth write coalesced for display %{public}@ at step %{public}@ due to debounce", type: .info, String(displayID), String(stepIndex))
    let workItem = DispatchWorkItem { [weak self] in
      self?.commitPendingWrites()
    }
    self.pendingWrite = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.writeDebounce - elapsed, execute: workItem)
  }

  private func commitPendingWrites() {
    self.pendingWrite?.cancel()
    self.pendingWrite = nil
    let writes = self.pendingIndex
    self.pendingIndex.removeAll()
    for (displayID, stepIndex) in writes where self.lastSentIndex[displayID] != stepIndex {
      guard let otherDisplay = self.displays.first(where: { $0.identifier == displayID }) as? OtherDisplay else {
        continue
      }
      // writeDDCValues degrades gracefully: a write the display ignores or does not ack cannot
      // crash or block, the slider simply has no visible effect (same behavior as preset color).
      otherDisplay.writeDDCValues(command: .selectColorPreset, value: Self.steps[stepIndex].value)
      self.lastSentIndex[displayID] = stepIndex
      self.lastWriteTime = Date()
      os_log("Color Warmth write sent for display %{public}@ at step %{public}@", type: .info, String(displayID), String(stepIndex))
    }
  }
}
