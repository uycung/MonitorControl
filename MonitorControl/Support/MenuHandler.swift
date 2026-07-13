//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import AppKit
import os.log

class MenuHandler: NSMenu, NSMenuDelegate {
  class PresetMenuReference: NSObject {
    let prefsId: String
    let presetId: UUID?
    init(prefsId: String, presetId: UUID?) {
      self.prefsId = prefsId
      self.presetId = presetId
    }
  }

  var combinedSliderHandler: [Command: SliderHandler] = [:]

  var nightShiftSliderHandler: NightShiftSliderHandler?

  var lastMenuRelevantDisplayId: CGDirectDisplayID = 0

  func clearMenu() {
    var items: [NSMenuItem] = []
    for i in 0 ..< self.items.count {
      items.append(self.items[i])
    }
    for item in items {
      self.removeItem(item)
    }
    self.combinedSliderHandler.removeAll()
    self.nightShiftSliderHandler = nil
  }

  func menuWillOpen(_: NSMenu) {
    self.updateMenuRelevantDisplay()
    self.nightShiftSliderHandler?.refreshStrength()
    self.refreshPresetCheckmarks(in: self)
    app.keyboardShortcuts.disengage()
  }

  func closeMenu() {
    self.cancelTrackingWithoutAnimation()
  }

  func updateMenus(dontClose: Bool = false) {
    os_log("Menu update initiated", type: .info)
    if !dontClose {
      self.cancelTrackingWithoutAnimation()
    }
    let menuIconPref = prefs.integer(forKey: PrefKey.menuIcon.rawValue)
    var showIcon = false
    if menuIconPref == MenuIcon.show.rawValue {
      showIcon = true
    } else if menuIconPref == MenuIcon.externalOnly.rawValue {
      let externalDisplays = DisplayManager.shared.displays.filter {
        CGDisplayIsBuiltin($0.identifier) == 0
      }
      if externalDisplays.count > 0 {
        showIcon = true
      }
    }
    app.updateStatusItemVisibility(showIcon)
    self.clearMenu()
    let currentDisplay = DisplayManager.shared.getCurrentDisplay()
    var displays: [Display] = []
    if !prefs.bool(forKey: PrefKey.hideAppleFromMenu.rawValue) {
      displays.append(contentsOf: DisplayManager.shared.getAppleDisplays())
    }
    displays.append(contentsOf: DisplayManager.shared.getOtherDisplays())
    displays = DisplayManager.shared.sortDisplaysByFriendlyName()
    let relevant = prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.relevant.rawValue
    let combine = prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue
    let numOfDisplays = displays.filter { !$0.isDummy }.count
    if numOfDisplays != 0 {
      let asSubMenu: Bool = (displays.count > 3 && !relevant && !combine && app.macOS10()) ? true : false
      var iterator = 0
      for display in displays where (!relevant || DisplayManager.resolveEffectiveDisplayID(display.identifier) == DisplayManager.resolveEffectiveDisplayID(currentDisplay!.identifier)) && !display.isDummy {
        iterator += 1
        if !relevant, !combine, iterator != 1, app.macOS10() {
          self.insertItem(NSMenuItem.separator(), at: 0)
        }
        self.updateDisplayMenu(display: display, asSubMenu: asSubMenu, numOfDisplays: numOfDisplays)
      }
      if combine {
        self.addCombinedDisplayMenuBlock()
      }
    }
    self.addNightShiftMenuItemIfEligible()
    self.addDefaultMenuOptions()
  }

  static func shouldShowNightShift(preferenceEnabled: Bool, nightShiftAvailable: Bool) -> Bool {
    preferenceEnabled && nightShiftAvailable
  }

  private func addNightShiftMenuItemIfEligible() {
    guard Self.shouldShowNightShift(preferenceEnabled: prefs.bool(forKey: PrefKey.showNightShift.rawValue), nightShiftAvailable: NightShiftController.shared.available) else {
      return
    }
    let sliderHandler = NightShiftSliderHandler()
    self.nightShiftSliderHandler = sliderHandler
    let item = NSMenuItem()
    item.view = sliderHandler.view
    self.insertItem(item, at: 0)
    if prefs.integer(forKey: PrefKey.menuIcon.rawValue) == MenuIcon.sliderOnly.rawValue {
      app.updateStatusItemVisibility(true)
    }
  }

  func addSliderItem(monitorSubMenu: NSMenu, sliderHandler: SliderHandler) {
    let item = NSMenuItem()
    item.view = sliderHandler.view
    monitorSubMenu.insertItem(item, at: 0)
    if app.macOS10() {
      let sliderHeaderItem = NSMenuItem()
      let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemGray, .font: NSFont.systemFont(ofSize: 12)]
      sliderHeaderItem.attributedTitle = NSAttributedString(string: sliderHandler.title, attributes: attrs)
      monitorSubMenu.insertItem(sliderHeaderItem, at: 0)
    }
  }

  func setupMenuSliderHandler(command: Command, display: Display, title: String) -> SliderHandler {
    if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue, let combinedHandler = self.combinedSliderHandler[command] {
      combinedHandler.addDisplay(display)
      display.sliderHandler[command] = combinedHandler
      return combinedHandler
    } else {
      let sliderHandler = command == .selectColorPreset ? ColorWarmthSliderHandler(display: display, command: command, title: title) : SliderHandler(display: display, command: command, title: title)
      if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue {
        self.combinedSliderHandler[command] = sliderHandler
      }
      display.sliderHandler[command] = sliderHandler
      return sliderHandler
    }
  }

  func addDisplayMenuBlock(addedSliderHandlers: [SliderHandler], blockName: String, monitorSubMenu: NSMenu, numOfDisplays: Int, asSubMenu: Bool) {
    if numOfDisplays > 1, prefs.integer(forKey: PrefKey.multiSliders.rawValue) != MultiSliders.relevant.rawValue, !DEBUG_MACOS10, #available(macOS 11.0, *) {
      class BlockView: NSView {
        override func draw(_: NSRect) {
          let radius = prefs.bool(forKey: PrefKey.showTickMarks.rawValue) ? CGFloat(4) : CGFloat(11)
          let outerMargin = CGFloat(15)
          let blockRect = self.frame.insetBy(dx: outerMargin, dy: outerMargin / 2 + 2).offsetBy(dx: 0, dy: outerMargin / 2 * -1 + 7)
          for i in 1 ... 5 {
            let blockPath = NSBezierPath(roundedRect: blockRect.insetBy(dx: CGFloat(i) * -1, dy: CGFloat(i) * -1), xRadius: radius + CGFloat(i) * 0.5, yRadius: radius + CGFloat(i) * 0.5)
            NSColor.black.withAlphaComponent(0.1 / CGFloat(i)).setStroke()
            blockPath.stroke()
          }
          let blockPath = NSBezierPath(roundedRect: blockRect, xRadius: radius, yRadius: radius)
          if [NSAppearance.Name.darkAqua, NSAppearance.Name.vibrantDark].contains(effectiveAppearance.name) {
            NSColor.systemGray.withAlphaComponent(0.3).setStroke()
            blockPath.stroke()
          }
          if ![NSAppearance.Name.darkAqua, NSAppearance.Name.vibrantDark].contains(effectiveAppearance.name) {
            NSColor.white.withAlphaComponent(0.5).setFill()
            blockPath.fill()
          }
        }
      }
      var contentWidth: CGFloat = 0
      var contentHeight: CGFloat = 0
      for addedSliderHandler in addedSliderHandlers {
        contentWidth = max(addedSliderHandler.view!.frame.width, contentWidth)
        contentHeight += addedSliderHandler.view!.frame.height
      }
      let margin = CGFloat(13)
      var blockNameView: NSTextField?
      if blockName != "" {
        contentHeight += 21
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.textColor, .font: NSFont.boldSystemFont(ofSize: 12)]
        blockNameView = NSTextField(labelWithAttributedString: NSAttributedString(string: blockName, attributes: attrs))
        blockNameView?.frame.size.width = contentWidth - margin * 2
        blockNameView?.alphaValue = 0.5
      }
      let itemView = BlockView(frame: NSRect(x: 0, y: 0, width: contentWidth + margin * 2, height: contentHeight + margin * 2))
      var sliderPosition = CGFloat(margin * -1 + 1)
      for addedSliderHandler in addedSliderHandlers {
        addedSliderHandler.view!.setFrameOrigin(NSPoint(x: margin, y: margin + sliderPosition + 13))
        itemView.addSubview(addedSliderHandler.view!)
        sliderPosition += addedSliderHandler.view!.frame.height
      }
      if let blockNameView = blockNameView {
        blockNameView.setFrameOrigin(NSPoint(x: margin + 13, y: contentHeight - 8))
        itemView.addSubview(blockNameView)
      }
      let item = NSMenuItem()
      item.view = itemView
      if addedSliderHandlers.count != 0 {
        monitorSubMenu.insertItem(item, at: 0)
      }
    } else {
      for addedSliderHandler in addedSliderHandlers {
        self.addSliderItem(monitorSubMenu: monitorSubMenu, sliderHandler: addedSliderHandler)
      }
    }
    self.appendMenuHeader(friendlyName: blockName, monitorSubMenu: monitorSubMenu, asSubMenu: asSubMenu, numOfDisplays: numOfDisplays)
  }

  func addCombinedDisplayMenuBlock() {
    if let sliderHandler = self.combinedSliderHandler[.audioSpeakerVolume] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
    if let sliderHandler = self.combinedSliderHandler[.selectColorPreset] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
    if let sliderHandler = self.combinedSliderHandler[.contrast] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
    if let sliderHandler = self.combinedSliderHandler[.brightness] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
    for otherDisplay in DisplayManager.shared.getOtherDisplays() where !otherDisplay.isSw() && !otherDisplay.isDummy {
      self.insertPresetMenuItems(for: otherDisplay, into: self, at: self.items.count, showDisplayName: true)
    }
  }

  func buildPresetMenuItems(for display: OtherDisplay, showDisplayName: Bool = false) -> [NSMenuItem] {
    display.seedBuiltinPresetsIfNeeded()
    display.migrateReadingModeBrightnessIfNeeded()
    display.migrateReadingModeContrastIfNeeded()
    let presets = display.loadPresets()
    var items: [NSMenuItem] = []
    var title = NSLocalizedString("Presets", comment: "Shown in menu")
    if showDisplayName {
      let friendlyName = display.readPrefAsString(key: .friendlyName) != "" ? display.readPrefAsString(key: .friendlyName) : display.name
      title += " (" + friendlyName + ")"
    }
    let headerItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    headerItem.isEnabled = false
    items.append(headerItem)
    for preset in presets {
      let item = NSMenuItem(title: preset.name, action: #selector(self.applyPresetClicked(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = PresetMenuReference(prefsId: display.prefsId, presetId: preset.id)
      item.state = display.isPresetActive(preset) ? .on : .off
      items.append(item)
    }
    let saveItem = NSMenuItem(title: NSLocalizedString("Save Current as…", comment: "Shown in menu"), action: #selector(self.saveCurrentAsPresetClicked(_:)), keyEquivalent: "")
    saveItem.target = self
    saveItem.representedObject = PresetMenuReference(prefsId: display.prefsId, presetId: nil)
    items.append(saveItem)
    if !presets.isEmpty {
      let editMenu = NSMenu()
      for preset in presets {
        let presetEditMenu = NSMenu()
        let entries: [(String, Selector)] = [
          (NSLocalizedString("Update with Current Values", comment: "Shown in menu"), #selector(self.updatePresetClicked(_:))),
          (NSLocalizedString("Rename…", comment: "Shown in menu"), #selector(self.renamePresetClicked(_:))),
          (NSLocalizedString("Delete", comment: "Shown in menu"), #selector(self.deletePresetClicked(_:))),
        ]
        for (title, action) in entries {
          let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
          item.target = self
          item.representedObject = PresetMenuReference(prefsId: display.prefsId, presetId: preset.id)
          presetEditMenu.addItem(item)
        }
        let presetItem = NSMenuItem(title: preset.name, action: nil, keyEquivalent: "")
        presetItem.submenu = presetEditMenu
        editMenu.addItem(presetItem)
      }
      let editItem = NSMenuItem(title: NSLocalizedString("Edit Presets", comment: "Shown in menu"), action: nil, keyEquivalent: "")
      editItem.submenu = editMenu
      items.append(editItem)
    }
    return items
  }

  func insertPresetMenuItems(for display: OtherDisplay, into menu: NSMenu, at index: Int, showDisplayName: Bool = false) {
    var insertionIndex = index
    for item in self.buildPresetMenuItems(for: display, showDisplayName: showDisplayName) {
      menu.insertItem(item, at: insertionIndex)
      insertionIndex += 1
    }
  }

  private func resolvePresetMenuReference(_ sender: NSMenuItem) -> (display: OtherDisplay, presetIndex: Int?)? {
    guard let reference = sender.representedObject as? PresetMenuReference, let display = (DisplayManager.shared.getOtherDisplays().first { $0.prefsId == reference.prefsId }) else {
      return nil
    }
    let presetIndex = display.loadPresets().firstIndex { $0.id == reference.presetId }
    return (display, presetIndex)
  }

  private func refreshPresetCheckmarks(in menu: NSMenu) {
    for item in menu.items {
      if item.action == #selector(self.applyPresetClicked(_:)), let (display, presetIndex) = self.resolvePresetMenuReference(item), let index = presetIndex {
        item.state = display.isPresetActive(display.loadPresets()[index]) ? .on : .off
      }
      if let submenu = item.submenu {
        self.refreshPresetCheckmarks(in: submenu)
      }
    }
  }

  private func promptForPresetName(currentName: String = "") -> String? {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Preset Name", comment: "Shown in the preset name dialog")
    alert.informativeText = NSLocalizedString("Enter a name for the preset.", comment: "Shown in the preset name dialog")
    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Shown in the preset name dialog"))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Shown in the preset name dialog"))
    let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    nameField.stringValue = currentName
    alert.accessoryView = nameField
    alert.window.initialFirstResponder = nameField
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else {
      return nil
    }
    let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? nil : name
  }

  @objc func applyPresetClicked(_ sender: NSMenuItem) {
    guard let (display, presetIndex) = self.resolvePresetMenuReference(sender), let index = presetIndex else {
      return
    }
    display.applyPreset(display.loadPresets()[index])
    self.refreshPresetCheckmarks(in: self)
  }

  @objc func saveCurrentAsPresetClicked(_ sender: NSMenuItem) {
    guard let (display, _) = self.resolvePresetMenuReference(sender), let name = self.promptForPresetName() else {
      return
    }
    var presets = display.loadPresets()
    presets.append(display.captureCurrentAsPreset(name: name))
    display.savePresets(presets)
    self.updateMenus()
  }

  @objc func updatePresetClicked(_ sender: NSMenuItem) {
    guard let (display, presetIndex) = self.resolvePresetMenuReference(sender), let index = presetIndex else {
      return
    }
    var presets = display.loadPresets()
    var updated = display.captureCurrentAsPreset(name: presets[index].name)
    updated.id = presets[index].id
    presets[index] = updated
    display.savePresets(presets)
  }

  @objc func renamePresetClicked(_ sender: NSMenuItem) {
    guard let (display, presetIndex) = self.resolvePresetMenuReference(sender), let index = presetIndex else {
      return
    }
    var presets = display.loadPresets()
    guard let name = self.promptForPresetName(currentName: presets[index].name) else {
      return
    }
    presets[index].name = name
    display.savePresets(presets)
    self.updateMenus()
  }

  @objc func deletePresetClicked(_ sender: NSMenuItem) {
    guard let (display, presetIndex) = self.resolvePresetMenuReference(sender), let index = presetIndex else {
      return
    }
    var presets = display.loadPresets()
    presets.remove(at: index)
    display.savePresets(presets)
    self.updateMenus()
  }

  func updateDisplayMenu(display: Display, asSubMenu: Bool, numOfDisplays: Int) {
    os_log("Addig menu items for display %{public}@", type: .info, "\(display.identifier)")
    let monitorSubMenu: NSMenu = asSubMenu ? NSMenu() : self
    var addedSliderHandlers: [SliderHandler] = []
    display.sliderHandler[.audioSpeakerVolume] = nil
    if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw(), !display.readPrefAsBool(key: .unavailableDDC, for: .audioSpeakerVolume), !prefs.bool(forKey: PrefKey.hideVolume.rawValue) {
      let title = NSLocalizedString("Volume", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .audioSpeakerVolume, display: display, title: title))
    }
    display.sliderHandler[.selectColorPreset] = nil
    let colorWarmthHardwareDDC = (display as? OtherDisplay).map { !$0.isSw() } ?? false
    let colorWarmthDDCAvailable = !display.readPrefAsBool(key: .unavailableDDC, for: .selectColorPreset)
    let showColorWarmth = prefs.bool(forKey: PrefKey.showColorWarmth.rawValue)
    if colorWarmthHardwareDDC, colorWarmthDDCAvailable, showColorWarmth {
      let title = NSLocalizedString("Color Warmth", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .selectColorPreset, display: display, title: title))
    } else {
      os_log("Skipping Color Warmth slider: hardwareDDC=%{public}@, selectColorPresetAvailable=%{public}@, showColorWarmth=%{public}@", type: .info, String(colorWarmthHardwareDDC), String(colorWarmthDDCAvailable), String(showColorWarmth))
    }
    display.sliderHandler[.contrast] = nil
    if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw(), !display.readPrefAsBool(key: .unavailableDDC, for: .contrast), prefs.bool(forKey: PrefKey.showContrast.rawValue) {
      let title = NSLocalizedString("Contrast", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .contrast, display: display, title: title))
    }
    display.sliderHandler[.brightness] = nil
    if !display.readPrefAsBool(key: .unavailableDDC, for: .brightness), !prefs.bool(forKey: PrefKey.hideBrightness.rawValue) {
      let title = NSLocalizedString("Brightness", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .brightness, display: display, title: title))
    }
    if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw(), prefs.integer(forKey: PrefKey.multiSliders.rawValue) != MultiSliders.combine.rawValue {
      self.insertPresetMenuItems(for: otherDisplay, into: monitorSubMenu, at: 0)
    }
    if prefs.integer(forKey: PrefKey.multiSliders.rawValue) != MultiSliders.combine.rawValue {
      self.addDisplayMenuBlock(addedSliderHandlers: addedSliderHandlers, blockName: display.readPrefAsString(key: .friendlyName) != "" ? display.readPrefAsString(key: .friendlyName) : display.name, monitorSubMenu: monitorSubMenu, numOfDisplays: numOfDisplays, asSubMenu: asSubMenu)
    }
    if addedSliderHandlers.count > 0, prefs.integer(forKey: PrefKey.menuIcon.rawValue) == MenuIcon.sliderOnly.rawValue {
      app.updateStatusItemVisibility(true)
    }
  }

  private func appendMenuHeader(friendlyName: String, monitorSubMenu: NSMenu, asSubMenu: Bool, numOfDisplays: Int) {
    let monitorMenuItem = NSMenuItem()
    if asSubMenu {
      monitorMenuItem.title = "\(friendlyName)"
      monitorMenuItem.submenu = monitorSubMenu
      self.insertItem(monitorMenuItem, at: 0)
    } else if app.macOS10(), numOfDisplays > 1 {
      let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemGray, .font: NSFont.boldSystemFont(ofSize: 12)]
      monitorMenuItem.attributedTitle = NSAttributedString(string: "\(friendlyName)", attributes: attrs)
      self.insertItem(monitorMenuItem, at: 0)
    }
  }

  func updateMenuRelevantDisplay() {
    if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.relevant.rawValue {
      if let display = DisplayManager.shared.getCurrentDisplay(), display.identifier != self.lastMenuRelevantDisplayId {
        os_log("Menu must be refreshed as relevant display changed since last time.")
        self.lastMenuRelevantDisplayId = display.identifier
        self.updateMenus(dontClose: true)
      }
    }
  }

  func addDefaultMenuOptions() {
    if !DEBUG_MACOS10, #available(macOS 11.0, *), prefs.integer(forKey: PrefKey.menuItemStyle.rawValue) == MenuItemStyle.icon.rawValue {
      let iconSize = CGFloat(18)
      let viewWidth = max(130, self.size.width)
      var compensateForBlock: CGFloat = 0
      if viewWidth > 230 { // if there are display blocks, we need to compensate a bit for the negative inset of the blocks
        compensateForBlock = 4
      }

      let menuItemView = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: iconSize + 10))

      let settingsIcon = NSButton()
      settingsIcon.bezelStyle = .regularSquare
      settingsIcon.isBordered = false
      settingsIcon.setButtonType(.momentaryChange)
      settingsIcon.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: NSLocalizedString("Settings…", comment: "Shown in menu"))
      settingsIcon.alternateImage = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: NSLocalizedString("Settings…", comment: "Shown in menu"))
      settingsIcon.alphaValue = 0.3
      settingsIcon.frame = NSRect(x: menuItemView.frame.maxX - iconSize * 3 - 20 - 17 + compensateForBlock, y: menuItemView.frame.origin.y + 5, width: iconSize, height: iconSize)
      settingsIcon.imageScaling = .scaleProportionallyUpOrDown
      settingsIcon.action = #selector(app.prefsClicked)

      let updateIcon = NSButton()
      updateIcon.bezelStyle = .regularSquare
      updateIcon.isBordered = false
      updateIcon.setButtonType(.momentaryChange)
      var symbolName = prefs.bool(forKey: PrefKey.showTickMarks.rawValue) ? "arrow.left.arrow.right.square" : "arrow.triangle.2.circlepath.circle"
      updateIcon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: NSLocalizedString("Check for updates…", comment: "Shown in menu"))
      updateIcon.alternateImage = NSImage(systemSymbolName: symbolName + ".fill", accessibilityDescription: NSLocalizedString("Check for updates…", comment: "Shown in menu"))

      updateIcon.alphaValue = 0.3
      updateIcon.frame = NSRect(x: menuItemView.frame.maxX - iconSize * 2 - 14 - 17 + compensateForBlock, y: menuItemView.frame.origin.y + 5, width: iconSize, height: iconSize)
      updateIcon.imageScaling = .scaleProportionallyUpOrDown
      updateIcon.action = #selector(app.updaterController.checkForUpdates(_:))
      updateIcon.target = app.updaterController

      let quitIcon = NSButton()
      quitIcon.bezelStyle = .regularSquare
      quitIcon.isBordered = false
      quitIcon.setButtonType(.momentaryChange)
      symbolName = prefs.bool(forKey: PrefKey.showTickMarks.rawValue) ? "multiply.square" : "xmark.circle"
      quitIcon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: NSLocalizedString("Quit", comment: "Shown in menu"))
      quitIcon.alternateImage = NSImage(systemSymbolName: symbolName + ".fill", accessibilityDescription: NSLocalizedString("Quit", comment: "Shown in menu"))
      quitIcon.alphaValue = 0.3
      quitIcon.frame = NSRect(x: menuItemView.frame.maxX - iconSize - 17 + compensateForBlock, y: menuItemView.frame.origin.y + 5, width: iconSize, height: iconSize)
      quitIcon.imageScaling = .scaleProportionallyUpOrDown
      quitIcon.action = #selector(app.quitClicked)

      menuItemView.addSubview(settingsIcon)
      menuItemView.addSubview(updateIcon)
      menuItemView.addSubview(quitIcon)
      let item = NSMenuItem()
      item.view = menuItemView
      self.insertItem(item, at: self.items.count)
    } else if prefs.integer(forKey: PrefKey.menuItemStyle.rawValue) != MenuItemStyle.hide.rawValue {
      if app.macOS10() {
        self.insertItem(NSMenuItem.separator(), at: self.items.count)
      }
      self.insertItem(withTitle: NSLocalizedString("Settings…", comment: "Shown in menu"), action: #selector(app.prefsClicked), keyEquivalent: ",", at: self.items.count)
      let updateItem = NSMenuItem(title: NSLocalizedString("Check for updates…", comment: "Shown in menu"), action: #selector(app.updaterController.checkForUpdates(_:)), keyEquivalent: "")
      updateItem.target = app.updaterController
      self.insertItem(updateItem, at: self.items.count)
      self.insertItem(withTitle: NSLocalizedString("Quit", comment: "Shown in menu"), action: #selector(app.quitClicked), keyEquivalent: "q", at: self.items.count)
    }
  }
}
