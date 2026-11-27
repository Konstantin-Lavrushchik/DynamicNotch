# Dynamic Notch

The iPhone Dynamic Island for the MacBook notch. It's a small SwiftUI menu-bar app that turns the notch into a live, springy island. It copies the iPhone 17 / 17 Pro Dynamic Island as closely as public macOS APIs allow.

## How it behaves (same as iPhone)

| iPhone | Dynamic Notch |
|---|---|
| Compact view: content left and right of the camera | ✅ |
| Minimal view: second activity as a separate bubble | ✅ click the bubble to switch |
| Expanded view: touch and hold | ✅ press and hold (or hover, optional) |
| Tap opens the app | ✅ click |
| Swipe up to collapse | ✅ two-finger swipe up, or drag up |
| Swipe sideways to hide activities | ✅ two-finger swipe sideways, swipe again to bring them back |
| Alerting updates pop the island open | ✅ |
| Hidden activity that needs attention comes back | ✅ (timer alarm) |

## What it shows

**Live Activities**
- **Now Playing** (Apple Music, Spotify): artwork, waveform in the album colour, progress you can drag, play/pause/next/previous
- **Timers**: several at once (like iOS 17+); the island shows the one ending soonest, expanded lists up to three with pause / cancel; a finished timer opens the island and rings until Stop or Repeat
- **Alarm**: rings in the island with Snooze and Stop; Snooze (9 minutes, like iPhone) shows a countdown
- **Stopwatch**: start, pause, lap, reset
- **Voice memo**: record from the island; live waveform; saved to `~/Documents/Dynamic Notch Recordings`
- **Downloads**: Safari, Chrome, Firefox, Edge; progress ring, "Downloaded" when finished
- **Microphone / camera in use**: orange and green dots

**System alerts**
- Charging (with battery %), low battery at 20 / 10 / 5 %; the battery turns yellow in Low Power Mode
- AirPods / headphones connected, with L / R / Case battery when macOS reports it
- Silent mode = output muted / unmuted
- Volume
- Unlock (the padlock springs open)

Start a timer, alarm, stopwatch or voice memo from the menu-bar icon or by right-clicking the island.

## Settings

- **Open at login**
- **Start minimized**: no window at launch (the first launch always shows Settings once)
- **Show icon in the Dock** / **Show icon in the menu bar**: with both hidden, right-click the island or open the app again to get to Settings
- Expand on hover, trackpad haptics, and an on/off switch for every activity and alert

Memory: about 16 MB idle and under 30 MB at the busiest (three timers, alarm, Settings open) (Activity Monitor's "Memory" column).

## Not possible on macOS (no public API)

Phone/FaceTime calls, Maps directions, Apple Pay, Face ID, other apps' Live Activities (including the iPhone's, which macOS 26 already shows in the menu bar), brightness. Now Playing only works for Music and Spotify, because other players have no public API.

## Install

Open `DynamicNotch-<version>.dmg` and drag **Dynamic Notch** to **Applications**.

## Build

Needs macOS 15+ and the Xcode Command Line Tools (full Xcode not required).

```bash
./build.sh            # builds build/DynamicNotch.app
./build.sh --install  # copies it to ~/Applications and starts it
tools/make-dmg.sh     # makes the drag-to-Applications installer in ~/Downloads
```

On first use macOS asks for Automation (Music/Spotify), Bluetooth, Microphone (voice memos) and Downloads folder access. The app is signed locally (ad-hoc), so it is not notarised.

### Testing hook

Start with `open --env DYNAMICNOTCH_DEBUG=1 ~/Applications/DynamicNotch.app`, then:

```bash
swiftc tools/dn.swift -o .build/dn
.build/dn timer:90        # also: stopwatch, expand, collapse, switch, alert:charging, alert:airpods
```
