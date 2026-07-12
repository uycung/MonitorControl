# MonitorControl Presets Fork 4.3.501

This personal fork of MonitorControl adds per-display presets and color-preset controls while retaining the upstream project's core brightness, contrast, volume and keyboard-control features.

## Highlights

- Per-display presets with built-in Reading Mode, Night Mode, Movie/Vivid and Standard profiles.
- Create custom profiles with **Save Current as…**, and update, rename or delete existing presets.
- The currently active preset is marked with a checkmark in the menu.
- Color Warmth slider using MCCS VCP `0x14`. Hardware support varies by monitor, and AVService-bridged displays may respond more slowly or inconsistently than brightness and contrast controls.
- Contrast and Color Warmth sliders are enabled by default on supported displays.
- Reading Mode is tuned to 70% brightness and 65% contrast.
- Sparkle automatic updates are disabled; fork updates are distributed manually through this repository's GitHub Releases.

## How to install

Download and unzip the app, copy `MonitorControl.app` to `/Applications`, then follow the unsigned-build instructions in the README's [Installing this build](README.md#installing-this-build) section. A one-time Gatekeeper override and Accessibility permission may be required.
