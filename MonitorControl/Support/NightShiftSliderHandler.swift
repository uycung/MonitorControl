//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import os.log

final class NightShiftSliderHandler: SliderHandler {
  private let nightShiftController: NightShiftControlling

  init(nightShiftController: NightShiftControlling = NightShiftController.shared) {
    self.nightShiftController = nightShiftController
    super.init(display: nil, command: .none, title: NSLocalizedString("Night Shift", comment: "Shown in menu"))
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      self.icon?.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: self.title)
      self.addInfoAffordance()
    }
    self.slider?.trackingEnded = { [weak self] in
      self?.commitCurrentStrength()
    }
    self.refreshStrength()
  }

  /// Not a ClickThroughImageView: tooltips are resolved via hitTest, and a click-through
  /// view always hitTests to nil, so it would never register as "under the mouse".
  @available(macOS 11.0, *)
  private func addInfoAffordance() {
    guard let view = self.view, let slider = self.slider else {
      return
    }
    let iconSize: CGFloat = 15
    let iconSpacing: CGFloat = 5
    let reservedWidth: CGFloat = 24

    // Keep the row width aligned with the other controls while reserving a dedicated trailing
    // slot for the info icon, outside the slider's rounded track.
    slider.frame.size.width -= reservedWidth
    let infoIcon = NSImageView(frame: NSRect(
      x: slider.frame.maxX + iconSpacing,
      y: slider.frame.midY - iconSize / 2,
      width: iconSize,
      height: iconSize
    ))
    infoIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    infoIcon.contentTintColor = NSColor.secondaryLabelColor
    infoIcon.imageAlignment = .alignCenter
    infoIcon.toolTip = NSLocalizedString(
      "Night Shift must be turned on in System Settings → Displays → Night Shift (or via Control Center) for this slider to have a visible, lasting effect. This slider only adjusts warmth strength — it does not turn Night Shift on or change its schedule.",
      comment: "Tooltip on the Night Shift slider's info icon"
    )
    view.addSubview(infoIcon)
  }

  func refreshStrength() {
    guard let strength = self.nightShiftController.refreshStrength() else {
      return
    }
    self.setValue(strength)
  }

  @objc override func valueChanged(slider: MCSlider) {
    let strength = self.preparedValue(for: slider)
    let didWrite = self.nightShiftController.setStrength(strength, commit: !slider.isTracking)
    if !didWrite {
      os_log("Night Shift slider write failed", type: .error)
    }
  }

  private func commitCurrentStrength() {
    guard let slider = self.slider else {
      return
    }
    let didWrite = self.nightShiftController.setStrength(slider.floatValue, commit: true)
    if !didWrite {
      os_log("Night Shift slider commit failed", type: .error)
    }
  }
}
