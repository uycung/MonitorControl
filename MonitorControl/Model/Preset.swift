//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation
import IOKit
import os.log

struct Preset: Codable, Equatable {
  var id = UUID()
  var name: String
  var brightness: Float? // normalized 0-1, nil = don't touch
  var contrast: Float? // normalized 0-1, nil = don't touch
  var colorPresetValue: UInt16? // raw MCCS value for VCP 0x14 (selectColorPreset), nil = don't touch
}

extension Display {
  func loadPresets() -> [Preset] {
    guard let data = prefs.data(forKey: PrefKey.presets.rawValue + self.prefsId) else {
      return []
    }
    return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
  }

  func savePresets(_ presets: [Preset]) {
    guard let data = try? JSONEncoder().encode(presets) else {
      return
    }
    prefs.set(data, forKey: PrefKey.presets.rawValue + self.prefsId)
  }

  func seedBuiltinPresetsIfNeeded() {
    guard !prefs.bool(forKey: PrefKey.presetsSeeded.rawValue + self.prefsId) else {
      return
    }
    os_log("Seeding built-in presets for display %{public}@", type: .info, self.prefsId)
    var presets = self.loadPresets()
    presets.append(contentsOf: [
      Preset(name: NSLocalizedString("Reading Mode", comment: "Built-in preset name"), brightness: 0.70, contrast: 0.65, colorPresetValue: 0x04), // 5000K, warmer
      Preset(name: NSLocalizedString("Night Mode", comment: "Built-in preset name"), brightness: 0.15, contrast: 0.65, colorPresetValue: 0x03), // 4000K, very warm
      Preset(name: NSLocalizedString("Movie/Vivid", comment: "Built-in preset name"), brightness: 0.90, contrast: 0.85, colorPresetValue: 0x08), // 9300K, cooler
      Preset(name: NSLocalizedString("Standard", comment: "Built-in preset name"), brightness: 0.75, contrast: 0.75, colorPresetValue: 0x05), // 6500K, neutral
    ])
    self.savePresets(presets)
    prefs.set(true, forKey: PrefKey.presetsSeeded.rawValue + self.prefsId)
    prefs.set(true, forKey: PrefKey.readingModeBrightnessMigrated.rawValue + self.prefsId)
    prefs.set(true, forKey: PrefKey.readingModeContrastMigrated.rawValue + self.prefsId)
  }

  /// One-time bump of the built-in Reading Mode brightness from the original seed value (0.40) to
  /// 0.65. Only a preset that still exactly matches everything Reading Mode was originally seeded
  /// with (name, brightness, contrast, color) is updated - a renamed, deleted or otherwise edited
  /// preset no longer matches and is left untouched.
  func migrateReadingModeBrightnessIfNeeded() {
    guard prefs.bool(forKey: PrefKey.presetsSeeded.rawValue + self.prefsId), !prefs.bool(forKey: PrefKey.readingModeBrightnessMigrated.rawValue + self.prefsId) else {
      return
    }
    var presets = self.loadPresets()
    if let index = presets.firstIndex(where: { $0.name == NSLocalizedString("Reading Mode", comment: "Built-in preset name") && $0.brightness == 0.40 && $0.contrast == 0.70 && $0.colorPresetValue == 0x04 }) {
      os_log("Migrating Reading Mode preset brightness to 0.65 for display %{public}@", type: .info, self.prefsId)
      presets[index].brightness = 0.65
      self.savePresets(presets)
    }
    prefs.set(true, forKey: PrefKey.readingModeBrightnessMigrated.rawValue + self.prefsId)
  }

  /// One-time adjustment of Reading Mode after the original brightness migration. Only the exact
  /// post-migration-1 default tuple is updated; renamed, deleted, edited or already-updated presets
  /// are left untouched.
  func migrateReadingModeContrastIfNeeded() {
    guard prefs.bool(forKey: PrefKey.presetsSeeded.rawValue + self.prefsId), !prefs.bool(forKey: PrefKey.readingModeContrastMigrated.rawValue + self.prefsId) else {
      return
    }
    var presets = self.loadPresets()
    if let index = presets.firstIndex(where: { $0.name == NSLocalizedString("Reading Mode", comment: "Built-in preset name") && $0.brightness == 0.65 && $0.contrast == 0.70 && $0.colorPresetValue == 0x04 }) {
      os_log("Migrating Reading Mode preset to brightness 0.70 and contrast 0.65 for display %{public}@", type: .info, self.prefsId)
      presets[index].brightness = 0.70
      presets[index].contrast = 0.65
      self.savePresets(presets)
    }
    prefs.set(true, forKey: PrefKey.readingModeContrastMigrated.rawValue + self.prefsId)
  }
}

extension OtherDisplay {
  func isPresetActive(_ preset: Preset) -> Bool {
    let tolerance: Float = 0.001
    if let brightness = preset.brightness, abs(self.getBrightness() - brightness) > tolerance {
      return false
    }
    if let contrast = preset.contrast, abs(self.readPrefAsFloat(for: .contrast) - contrast) > tolerance {
      return false
    }
    if let colorPresetValue = preset.colorPresetValue {
      guard self.prefExists(for: .selectColorPreset), let index = ColorWarmthSliderHandler.steps.firstIndex(where: { $0.value == colorPresetValue }) else {
        return false
      }
      let normalized = Float(index) / Float(ColorWarmthSliderHandler.steps.count - 1)
      if abs(self.readPrefAsFloat(for: .selectColorPreset) - normalized) > tolerance {
        return false
      }
    }
    return true
  }

  func applyPreset(_ preset: Preset) {
    os_log("Applying preset %{public}@ for display %{public}@", type: .info, preset.name, self.prefsId)
    if !self.isSw() {
      // Color first: some displays reset brightness/contrast when the color mode changes. A write
      // the display does not support is silently ignored and cannot block the writes that follow.
      if let colorPresetValue = preset.colorPresetValue, !self.readPrefAsBool(key: .unavailableDDC, for: .selectColorPreset) {
        self.writeDDCValues(command: .selectColorPreset, value: colorPresetValue)
        if let index = ColorWarmthSliderHandler.steps.firstIndex(where: { $0.value == colorPresetValue }) {
          let normalized = Float(index) / Float(ColorWarmthSliderHandler.steps.count - 1)
          self.savePref(normalized, for: .selectColorPreset)
          self.sliderHandler[.selectColorPreset]?.setValue(normalized, displayID: self.identifier)
        }
      }
      if let contrast = preset.contrast, !self.readPrefAsBool(key: .unavailableDDC, for: .contrast) {
        self.writeDDCValues(command: .contrast, value: self.convValueToDDC(for: .contrast, from: contrast))
        self.savePref(contrast, for: .contrast)
        self.sliderHandler[.contrast]?.setValue(contrast, displayID: self.identifier)
      }
    }
    if let brightness = preset.brightness, !self.readPrefAsBool(key: .unavailableDDC, for: .brightness) {
      _ = self.setBrightness(brightness)
      self.sliderHandler[.brightness]?.setValue(brightness, displayID: self.identifier)
      self.brightnessSyncSourceValue = brightness
    }
  }

  func captureCurrentAsPreset(name: String) -> Preset {
    var preset = Preset(name: name)
    preset.brightness = self.getBrightness()
    if !self.isSw(), !self.readPrefAsBool(key: .unavailableDDC, for: .contrast) {
      preset.contrast = self.readPrefAsFloat(for: .contrast)
    }
    // The current color preset can only be captured via a DDC read. If the read fails (display
    // does not support VCP 0x14 or does not reply), the preset simply won't touch color.
    if !self.isSw() {
      let delay = self.readPrefAsBool(key: .longerDelay) ? UInt64(40 * kMillisecondScale) : nil
      if let values = self.readDDCValues(for: .selectColorPreset, tries: UInt(max(self.pollingCount, 1)), minReplyDelay: delay), values.current & 0xFF != 0 {
        preset.colorPresetValue = values.current & 0xFF
      }
    }
    return preset
  }
}
