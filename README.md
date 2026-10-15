# Notch

Your MacBook's notch, put to work. Hover over it to open it up, with what's playing, what's next on your
calendar, the weather and a tray for files. While it's closed it shows the volume, brightness, charging,
AirPods and Focus changes as they happen.

- **Now Playing:** artwork, playback controls and a waveform that moves with the music, from any player.
- **Calendar:** today's events, a Join button for video calls, and when to leave for events that have a place.
- **Weather:** where you are, or any city you pick.
- **File tray:** drop files, text or links on the notch to park them, then drag them out, AirDrop them or
  Quick Look them. Select several with ⌘ or ⇧.
- **HUDs:** volume, brightness and keyboard backlight show up in the notch instead of the middle of your screen.
- **Lock screen:** what's playing and the weather, right on the lock screen.

## Requirements

- macOS 26 Tahoe or later, on Apple silicon or Intel.
- A MacBook with a notch is best. On other Macs and on external displays, Notch draws one at the top of
  the screen (Settings › General › Display on).

## Install

Paste this into Terminal:

```sh
curl -fsSL https://github.com/FGXB1/notch/releases/latest/download/install.sh | sh
```

It downloads the latest release, puts Notch in Applications and opens it. A welcome window then walks you
through the permissions Notch can use.

<details>
<summary>Installing by hand instead</summary>

1. Download `Notch-<version>.dmg` from the [latest release](../../releases/latest), open it and drag
   **Notch** into **Applications**.
2. Notch isn't notarized by Apple, so macOS won't open a copy downloaded in a browser. Clear its quarantine
   flag once in Terminal (the one-line installer doesn't need this, because curl never sets the flag):

   ```sh
   xattr -dr com.apple.quarantine /Applications/Notch.app
   ```

3. Open Notch from Applications.
</details>

You only install once: Notch updates itself after that.

Notch has no Dock icon. To get to Settings, click the gear in the open notch, or open Notch again from
Applications or Spotlight. Quit it from Settings › General. It checks for updates once a day; you can check
yourself from Settings › About.

## Permissions

Every one is optional. Without one, that feature just isn't there.

| Permission | What it's for |
| --- | --- |
| Calendar | Your events, Join buttons and when to leave. |
| Accessibility | Showing Notch's volume and brightness HUD instead of the system's, and noticing full-screen apps. |
| Bluetooth | Your AirPods' battery when they connect. |
| Location | Local weather, and travel time to events. You can type a city instead. |
| System Audio Recording | Making the waveform move with the music. Notch reads only the loudness, live; nothing is recorded or kept. |
| Automation | Asked for the first time Notch controls a music app that needs it. |

## Privacy

Notch has no accounts, analytics or tracking. The only things it sends over the network:

- **Weather:** your approximate location (rounded to about a kilometre), or the city you typed, to
  [Open-Meteo](https://open-meteo.com).
- **Travel time and city search:** event addresses and the city you typed, to Apple Maps.
- **Updates:** a daily check of this repository's latest release, which includes Notch's version and your
  macOS version.

Files you drop on the tray are copied to `~/Library/Application Support/Notch/Tray` and stay on your Mac.

## Uninstall

Quit Notch (Settings › General › Quit Notch), drag it from Applications to the Trash, then optionally delete
`~/Library/Application Support/Notch` and `~/Library/Preferences/dev.ishan.Notch.plist`.

## Building it yourself

You'll need Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and CMake
(`brew install xcodegen cmake`).

```sh
git clone --recurse-submodules https://github.com/FGXB1/notch.git notch
cd notch
Scripts/run.sh                                  # builds Debug and launches it
swift test --package-path Packages/NotchKit     # unit tests
```

Builds are signed ad hoc, so macOS asks for its permissions again after every rebuild. To stop that, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put in your team ID; a free Apple account
works.

### Making a release

`Scripts/release.sh` builds the universal app, signs it, notarizes it when there's a Developer ID, makes the
disk image and writes the update feed. Settings are in `Config/release.env`.

```sh
Scripts/release.sh keys                  # once: create the key updates are signed with (back it up!)
Scripts/release.sh 1.2.0 notes.md        # build build/release/1.2.0/Notch-1.2.0.dmg and appcast.xml
Scripts/release.sh publish 1.2.0         # upload them as the v1.2.0 GitHub release
```

`publish` attaches the disk image, `appcast.xml` (installed copies look for it in the latest release, so
every release needs one) and `install.sh`, the one-line installer with this repository filled in.

## License

MIT; see [LICENSE](LICENSE).

## Credits

Now Playing uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg.
Updates by [Sparkle](https://sparkle-project.org), settings by [Defaults](https://github.com/sindresorhus/Defaults),
and weather data by [Open-Meteo](https://open-meteo.com) (CC BY 4.0). Their licenses are in
`App/Acknowledgements.txt`, and in Settings › About › Acknowledgements.
