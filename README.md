# Dock Glass for KDE Plasma

A macOS-like dock for KDE Plasma 6: a glass pill, icons that magnify continuously and spread apart under the pointer, a launch bounce, windows that pour out of their dock icon, and a stack of places that springs out of the Files icon. It is the Plasma port of [Dock Glass](https://github.com/atarico/dock-glass), the GNOME Shell extension.

> [!NOTE]
> **Early project.** Developed and tested on KDE neon with Plasma, KWin 6.8.1 and Qt 6.11 on Wayland, with one screen and the dock at the bottom. Values are hardcoded for now, and it is not on the KDE Store yet.

## Features

| Feature | What you see |
|---------|--------------|
| Magnification | Icons grow from their bottom edge as the pointer moves over the dock, 1.4x under it and back to rest size three icons away. No icon ever shrinks: neighbors spread apart and the pill widens with them, each end following the icons at its side |
| Glass pill | A fully rounded dock with a light rim, lit from above, blurred by KWin. With the [Glass](#glass) KWin effect, what passes behind it bends like through a lens |
| Name bubble | The name of the app under the pointer, in a small bubble above its icon |
| Launch bounce | An icon bounces until the app it launched shows its window, or 10 seconds pass |
| Genie | Minimizing pours a window into its dock icon and restoring pours it back out, with KWin's Magic Lamp. The first window of an app also pours out of its icon, with the Dock Glass Genie KWin effect |
| Files places stack | With no file manager windows open, a click on its icon fans out the places Dolphin shows (home, Desktop, Documents, Downloads, Music, Pictures, Videos and your bookmarks), with an entry on top that opens the file manager |
| System group | After a separator: the pinned file manager, the Trash (full or empty, opens on click) and an app launcher that opens Plasma's application menu |
| Pinning | Drag an app from the menu onto the dock to pin it where you drop it. Right-click an icon to open a new window, pin or unpin it, or close its windows |
| Hiding | Set to Dodge Windows, the dock hides while a window touches it and comes back when you push the pointer against the bottom edge |
| Running dot | One small dot under each open app |

## Install

Dock Glass has three parts: the **widget** that draws the dock, the **Plasma Style** that makes its panel a glass pill, and optional **KWin effects** for the glass and the genie.

1. Clone the repository and install the widget and the style:
   ```sh
   git clone https://github.com/atarico/dock-glass-kde.git
   cd dock-glass-kde
   kpackagetool6 -t Plasma/Applet -i package
   kpackagetool6 -t Plasma/Theme -i plasma-style
   ```
2. Choose the style: System Settings > Colors & Themes > Plasma Style > **Dock Glass**, or run `plasma-apply-desktoptheme dockglass`.
3. Add the dock's panel: right-click the desktop, **Add Panel** > **Empty Panel**, then in its settings:

   | Setting | Value |
   |---------|-------|
   | Position | Bottom |
   | Alignment | Center |
   | Width | Fit content |
   | Visibility | Dodge Windows |
   | Style | Floating |
   | Panel height | 64 |

4. Add the **Dock Glass** widget to that panel, and nothing else.
5. If your old panel is still at the bottom, move it to the top, and remove its **Icons-only Task Manager** or **Task Manager**: otherwise minimizing animates toward it instead of the dock.
6. Move the pointer over the dock: the icon under it grows above the pill and its neighbors spread apart.

To update, run `git pull` and the same two `kpackagetool6` commands with `-u` instead of `-i`, then `systemctl --user restart plasma-plasmashell`. To uninstall, remove the panel and run `kpackagetool6 -t Plasma/Applet -r io.github.atarico.dockglass` and `kpackagetool6 -t Plasma/Theme -r dockglass`.

## Recommended setup

The widget and the style give the dock and its pill. The rest of the look comes from KWin and a few Plasma settings.

### Glass

KWin's own blur frosts what is behind the pill. For the liquid glass of the original, where the background shows through slightly enlarged and bends at the rounded ends, use the community [Glass](https://github.com/AndyKaslana/kwin-effects-glass) effect, a fork of KWin's blur with refraction. It is built against your KWin, so it has to be rebuilt after each Plasma update. On KDE neon or Ubuntu 24.04:

```sh
sudo apt install git cmake g++ extra-cmake-modules qt6-tools-dev kwin-dev libkf6configwidgets-dev \
  gettext libkf6crash-dev libkf6globalaccel-dev libkf6kio-dev libkf6service-dev libkf6notifications-dev \
  libkf6kcmutils-dev libkdecorations3-dev libxcb-composite0-dev libxcb-randr0-dev libxcb-shm0-dev \
  libvulkan-dev libplasma-dev
git clone https://github.com/AndyKaslana/kwin-effects-glass
cd kwin-effects-glass
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
```

Then turn it on in place of the blur, with the settings that match the original's look, and log out and back in:

```sh
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key glassEnabled true
g="kwriteconfig6 --file kwinrc --group Effect-blurplus --key"
$g BlurStrength 2;  $g DockBlurStrength 1;  $g DockBlurFinetune 0;  $g DockCornerRadius 32
$g RefractionStrength 10;  $g RefractionEdgeSize 6;  $g RefractionOffsetStrength 8
$g BodyRefraction true;  $g RimSpecular true;  $g RimWidth 10;  $g EdgeAA true
```

The blur has to stay light (dock strength 1): with the defaults the pill still looks frosted.

### Genie

**Minimize and restore.** In System Settings > Window Management > Desktop Effects, turn on **Magic Lamp**, which replaces Squash. The dock tells KWin where each icon is, so the genie aims at it.

**Open.** The Dock Glass Genie effect in `kwin-effect/` pours the first window of an app out of its dock icon, with Magic Lamp's shape and duration. Later windows of a running app keep Plasma's open animation. It needs the same build packages as Glass and is rebuilt the same way after each Plasma update:

```sh
cd kwin-effect
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
kwriteconfig6 --file kwinrc --group Plugins --key dockglassgenieEnabled true
```

Log out and back in to load it. KWin never unloads an effect it has loaded, so a rebuilt effect also needs a new session.

### Showing the hidden dock

KWin shows a hidden panel once the pointer has pushed against the screen edge for a moment. With the default of 75 ms, passing the pointer along the bottom of a web page can bring the dock up by accident. A longer push avoids it:

```sh
kwriteconfig6 --file kwinrc --group Windows --key ElectricBorderDelay 250
qdbus6 org.kde.KWin /KWin reconfigure
```

This is KWin's setting for every screen edge, so hot corners need the same push.

### A one-row top bar

For a clean top bar like Ubuntu's or macOS's, set the top panel to **Not floating** with a **Panel height** of 32, which the Dock Glass style allows. Then:

- Keep the **Application Launcher** on the left: the dock's launcher icon opens it.
- Put the **Digital Clock** between two **Panel Spacers**, and in its settings show the date **Beside time** with a custom format such as `ddd d MMM ` (the trailing space separates the date from the time).
- Keep the **System Tray** on the right, and remove **Peek at Desktop** and the margins separator.

## Compatibility

| Component | Status |
|-----------|--------|
| Plasma 6.8 (KWin 6.8, Qt 6.11) | Tested on KDE neon, Wayland |
| Plasma 6.0 to 6.7 | Not tested |
| Plasma 5 | Not supported: the widget is written for Plasma 6 |
| X11 | Not supported: the icons are drawn in a Wayland layer-shell window |
| Dock position | Bottom only |
| Screens | One; several screens are not handled yet |
| Glass effect | Third-party; the fork above is the one tested on Plasma 6.8 |

## Known limitations

- **Plasma internals.** To make the pill grow with the icons and stay a full pill, the widget moves, sizes and restyles the background item of Plasma's `Panel.qml`. A Plasma update that reshapes it breaks the pill, though not the icons: the dock then logs that the panel background was not found.
- **Rebuilt effects.** Glass and Dock Glass Genie link against KWin and have to be rebuilt after every Plasma update. A build left over from an older KWin may crash KWin when you log in; rebuild it, or remove it from `/usr/lib/x86_64-linux-gnu/qt6/plugins/kwin/effects/plugins/` and turn it off in `~/.config/kwinrc`.
- **Hardcoded values.** The magnification peak, its reach, the icon size and the pinned apps' defaults are fixed until a settings page exists.
- **Translations.** The context menu is in English. The bubble, the Trash and the places use Plasma's and Dolphin's own translations.
- **Places stack.** Only the fan exists: with more than ten places, the first nine show. The original switches to a grid.
- **Other widgets.** Adding another widget to the dock's panel breaks its layout.
- **Panel position.** The dock reads where its panel is every 250 ms, so after moving or resizing the panel the icons can lag for a moment.

<details>
<summary><strong>How it works</strong></summary>

- **Overlay.** A Plasma panel draws only inside its own window, too short for magnified icons. The widget keeps invisible click targets on the panel at the rest layout and draws the icons in a separate, input-transparent layer-shell window above it, with room to grow. The spread keeps the point under the pointer fixed, so the icon drawn there is the one whose rest slot takes the click.
- **Pill.** Plasma moves and resizes a panel in separate frames, so a panel that followed the spread jittered. The panel instead keeps the width of the widest spread and never moves, and every frame the widget moves and sizes Plasma's own panel background, the item KWin blurs, so each end of the pill follows the icons at its side.
- **Style.** Plasma never makes a panel thinner than its background's top and bottom borders. The style's backgrounds hold two frames: a `dock-` one with 32 px corners, which the widget selects so the 64 px dock is a full pill, and a plain one with 16 px corners for other panels. `scripts/panel-background.mjs` writes them.
- **Stacking.** The overlay shares KWin's layer with the panels, where the window shown last goes on top. When a panel goes over it, the widget shows a fresh copy of the overlay and drops the old one once the copy has drawn. The overlay is not a transient of the panel, since Plasma never hides a panel while one of its transients is visible.
- **Hiding.** The icons slide with Plasma's panel: out while a window touches it, in when the pointer is back on it, by the panel's height, in KWin's Sliding Popups timing (200 ms, OutCubic in, InCubic out).
- **Genie.** Each icon publishes its rest place to KWin, which Magic Lamp uses for minimize and restore. Dock Glass Genie runs Magic Lamp's deformation from the icon to the window for the first window of an app, hiding it until the dock has published its icon, at most 400 ms.

</details>

## Development

| Path | Role |
|------|------|
| `package/contents/ui/main.qml` | The widget: tasks, click targets, magnification, pill, hiding, menus, drops |
| `package/contents/ui/Overlay.qml` | The layer-shell window that draws the icons |
| `package/contents/ui/DockIcon.qml` | One icon as drawn: scale, spread, bounce, running dot, name bubble |
| `package/contents/ui/Stack.qml` | The Files places stack |
| `package/contents/ui/magnifier.mjs` | Pure magnification math, from the original |
| `package/contents/ui/stackLayout.mjs` | Pure stack layout math, from the original |
| `package/contents/ui/places.mjs` | Reads the places from Dolphin's bookmarks |
| `plasma-style/` | The Dock Glass Plasma Style |
| `kwin-effect/` | The Dock Glass Genie KWin effect |
| `scripts/panel-background.mjs` | Writes the style's panel backgrounds |
| `scripts/vm.sh` | Runs the KDE neon test virtual machine |
| `scripts/vm-deploy.sh` | Installs the widget and the style in that machine and restarts Plasma |
| `scripts/vm-effect.sh` | Builds and installs the genie effect in that machine |

The pure math and the places parser have no QML imports, so Node.js 22 or newer tests them from the repository root:

```sh
node --test
```

The rest is checked by hand in a KDE neon virtual machine. `sh scripts/vm.sh install` boots the installer once (the ISO goes in `~/vms/kde-neon/`), `sh scripts/vm.sh` starts the installed machine with SSH on `127.0.0.1:2222`, and `sh scripts/vm-deploy.sh` installs the current code there. Watch for errors with:

```sh
journalctl --user -f -o cat | grep -i -E "dockglass|qml"
```

## License

[GPL-3.0-or-later](LICENSE). Copyright (C) 2026 atarico.

`magnifier.mjs` and `stackLayout.mjs` come from [Dock Glass](https://github.com/atarico/dock-glass). The Dock Glass Genie effect is derived from the Magic Lamp effect of [KWin](https://invent.kde.org/plasma/kwin) 6.8.1 by Martin Gräßlin and the KWin team (GPL-2.0-or-later).
