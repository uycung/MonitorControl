//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import os.log

protocol NightShiftOverlayPresenting: AnyObject {
  func show(message: String, relativeTo view: NSView)
  func hide()
}

final class NightShiftOverlayPresenter: NightShiftOverlayPresenting {
  private let popover: NSPopover

  init() {
    self.popover = NSPopover()
    self.popover.animates = false
    self.popover.behavior = .applicationDefined
  }

  func show(message: String, relativeTo view: NSView) {
    let label = NSTextField(wrappingLabelWithString: message)
    let textWidth: CGFloat = 280
    let textBounds = (message as NSString).boundingRect(
      with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: label.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]
    )
    label.frame = NSRect(x: 10, y: 10, width: textWidth, height: ceil(textBounds.height))
    let contentViewController = NSViewController()
    contentViewController.view = NSView(frame: NSRect(x: 0, y: 0, width: textWidth + 20, height: label.frame.height + 20))
    contentViewController.view.addSubview(label)
    self.popover.contentViewController = contentViewController
    if self.popover.isShown {
      self.popover.performClose(nil)
    }
    self.popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
  }

  func hide() {
    self.popover.performClose(nil)
  }
}

final class NightShiftInfoIconView: NSImageView {
  let message: String
  private let overlayPresenter: NightShiftOverlayPresenting

  init(frame frameRect: NSRect, message: String, overlayPresenter: NightShiftOverlayPresenting) {
    self.message = message
    self.overlayPresenter = overlayPresenter
    super.init(frame: frameRect)
    self.addTrackingArea(NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    ))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    nil
  }

  override func mouseEntered(with _: NSEvent) {
    self.showHoverOverlay()
  }

  override func mouseExited(with _: NSEvent) {
    self.hideHoverOverlay()
  }

  func showHoverOverlay() {
    self.overlayPresenter.show(message: self.message, relativeTo: self)
  }

  func hideHoverOverlay() {
    self.overlayPresenter.hide()
  }

  deinit {
    self.overlayPresenter.hide()
  }
}

final class NightShiftSliderHandler: SliderHandler {
  final class TrackingSliderCell: MCSliderCell {
    var trackingStarted: (() -> Void)?

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
      self.trackingStarted?()
      return super.startTracking(at: startPoint, in: controlView)
    }

    func notifyTrackingStarted() {
      self.trackingStarted?()
    }
  }

  static let infoMessage = NSLocalizedString(
    "Night Shift must be turned on in System Settings → Displays → Night Shift (or via Control Center) for this slider to have a visible, lasting effect. This slider only adjusts warmth strength — it does not turn Night Shift on or change its schedule.",
    comment: "Tooltip on the Night Shift slider's info icon"
  )

  static let disabledMessage = NSLocalizedString(
    "Night Shift is off. Enable it in System Settings → Displays → Night Shift for warmth changes to have a visible effect.",
    comment: "Shown after dragging the Night Shift strength slider while Night Shift is disabled"
  )

  private let nightShiftController: NightShiftControlling
  private let warningOverlayPresenter: NightShiftOverlayPresenting
  private var warningDismissWorkItem: DispatchWorkItem?

  init(
    nightShiftController: NightShiftControlling = NightShiftController.shared,
    warningOverlayPresenter: NightShiftOverlayPresenting = NightShiftOverlayPresenter()
  ) {
    self.nightShiftController = nightShiftController
    self.warningOverlayPresenter = warningOverlayPresenter
    super.init(display: nil, command: .none, title: NSLocalizedString("Night Shift", comment: "Shown in menu"))
    self.installTrackingStartHandler()
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      self.icon?.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: self.title)
      self.addInfoAffordance()
    }
    self.slider?.trackingEnded = { [weak self] in
      self?.commitCurrentStrength()
    }
    self.refreshStrength()
  }

  static func shouldShowDisabledMessage(nightShiftEnabled: Bool) -> Bool {
    !nightShiftEnabled
  }

  private func installTrackingStartHandler() {
    guard let slider = self.slider, let oldCell = slider.cell as? MCSliderCell else {
      return
    }
    let target = slider.target
    let action = slider.action
    let minValue = slider.minValue
    let maxValue = slider.maxValue
    let value = slider.doubleValue
    let trackingCell = TrackingSliderCell()
    trackingCell.numOfTickmarks = oldCell.numOfTickmarks
    trackingCell.isHighlightDisplayItems = oldCell.isHighlightDisplayItems
    trackingCell.displayHighlightItems = oldCell.displayHighlightItems
    slider.cell = trackingCell
    slider.target = target
    slider.action = action
    slider.minValue = minValue
    slider.maxValue = maxValue
    slider.doubleValue = value
    trackingCell.trackingStarted = { [weak self] in
      self?.handleTrackingStarted()
    }
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
    let infoIcon = NightShiftInfoIconView(
      frame: NSRect(
        x: slider.frame.maxX + iconSpacing,
        y: slider.frame.midY - iconSize / 2,
        width: iconSize,
        height: iconSize
      ),
      message: Self.infoMessage,
      overlayPresenter: NightShiftOverlayPresenter()
    )
    infoIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    infoIcon.contentTintColor = NSColor.secondaryLabelColor
    infoIcon.imageAlignment = .alignCenter
    view.addSubview(infoIcon)
  }

  private func handleTrackingStarted() {
    guard let nightShiftEnabled = self.nightShiftController.isNightShiftEnabled(), Self.shouldShowDisabledMessage(nightShiftEnabled: nightShiftEnabled), let slider = self.slider else {
      return
    }
    self.warningOverlayPresenter.show(message: Self.disabledMessage, relativeTo: slider)
    self.warningDismissWorkItem?.cancel()
    let dismissWorkItem = DispatchWorkItem { [weak self] in
      self?.warningOverlayPresenter.hide()
    }
    self.warningDismissWorkItem = dismissWorkItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismissWorkItem)
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

  deinit {
    self.warningDismissWorkItem?.cancel()
    self.warningOverlayPresenter.hide()
  }
}
