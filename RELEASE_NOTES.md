# MonitorControl 4.3.502 — Night Shift Integration

This release adds a native Night Shift strength control to the MonitorControl menu while preserving the fork's per-display presets and Color Warmth controls.

## What's new

- Adjust the system Night Shift warmth strength directly from the menu bar.
- The Night Shift row appears only while a built-in display is active and updates automatically when displays or the MacBook lid state change.
- With multiple displays, Night Shift is placed first inside the built-in display's control box; with only the built-in display, it remains a top-level control.
- The info icon now shows its explanation immediately on hover without the standard AppKit tooltip delay.
- Dragging the slider while Night Shift is disabled shows a non-blocking three-second reminder to enable it in System Settings.
- Slider dragging and commit-on-release behavior remain unchanged.

## Also included

- Per-display presets with built-in Reading Mode, Night Mode, Movie/Vivid and Standard profiles.
- Custom preset creation, updating, renaming and deletion.
- Color Warmth control for supported external displays using MCCS VCP `0x14`.
- Sparkle automatic updates remain disabled; fork releases are distributed manually through GitHub Releases.

## How to install

Download `MonitorControl-4.3.502-presets.zip`, unzip it, copy `MonitorControl.app` to `/Applications`, then follow the unsigned-build instructions in the README's [Installing this build](README.md#installing-this-build) section. A one-time Gatekeeper override and Accessibility permission may be required.
