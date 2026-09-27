# OXCE for iOS — iPad input fork

A repository with everything needed to build OXCE (OpenXcom Extended) for iOS.

This is a personal fork of [MeridianOXC/openxcom-ios](https://github.com/MeridianOXC/openxcom-ios),
focused on making the game properly playable on an iPad — with a Magic Keyboard,
a trackpad, a mouse, or just your fingers.

> ### ⚠️ These changes were made with AI
>
> Every change in this fork that differs from upstream was written by **Claude
> (Anthropic), an AI coding assistant**, working under my direction. I reviewed
> the changes and tested them on a real iPad, but I did not write the code.
>
> Every commit says so in its message. Please keep that in mind before using
> this, and especially before copying anything from it into another project.

---

## What's different from upstream

### Taps and clicks land where you tap

Previously, if you switched letterboxing on, taps did not land where you
touched. It was fine in the middle of the screen and got steadily worse towards
the top and bottom edges — near the edge you could be a whole row of tiles out.
The game was drawing the picture in one place and reading your finger in
another. Both now agree, so a tap hits what is under it, anywhere on screen.

### The trackpad and mouse work properly

**Hover now works.** Moving the pointer without clicking highlights buttons and
shows tooltips, the way it does on a desktop. Before, nothing happened until
you actually clicked — so you had to click a thing to find out what it was.

**Right click works.** A two-finger click on the trackpad, or the right button
on a mouse, does what it does on the desktop.

**Middle click works** with a real mouse — handy for opening the Ufopaedia entry
for an item straight from a list.

### Keyboard shortcuts work

A Magic Keyboard is now a real keyboard. All of the game's keyboard shortcuts
respond, and **Ctrl, Alt and Shift** work — including combinations like
Ctrl-clicking an item to see where it is stored.

Typing names for saves, bases and soldiers worked before and still does.

### Touch gestures in the battlescape

Playing with fingers alone, the battlescape now understands:

| Gesture | Does |
|---|---|
| One finger, tap | Left click |
| One finger, drag | Pan the map |
| Two fingers, tap | Right click — turns the selected soldier |
| Two fingers, hold | Middle click |
| Two fingers, drag | Change map level (up/down) |

This means you can right click and middle click without reaching for the
on-screen button bar.

Because two-finger tap now turns a soldier, the older **Swipe** and **Hold to
turn** options are switched off by default. They still exist in the Battlescape
options if you prefer them — but note that "hold to turn" will fight with
one-finger panning.

### Under the hood

SDL — the library the game uses to talk to the screen, sound and input — was
eight years old (2.0.8, from 2018). It is now **2.32.10**. Apple's own support
for iPad pointers and keyboards arrived long after 2.0.8, which is why none of
that worked before.

---

## Getting the source code

Clone recursively so the submodules come with it:

    $ git clone --recursive https://github.com/TobiWahnKenobi/openxcom-ios

Or, if your git client doesn't support recursive cloning:

    $ git clone https://github.com/TobiWahnKenobi/openxcom-ios
    $ cd openxcom-ios
    $ git submodule update --init --recursive

## Building the app

**First, on a new machine, install Apple's Metal toolchain:**

    $ xcodebuild -downloadComponent MetalToolchain

Xcode 26 does not include it, and the build fails immediately without it. It is
a ~700 MB download and does not ask for your password.

Then go to `Sources/OpenXcom/xcode-ios` and open `OpenXcom.xcodeproj`. This
should open Xcode with all subprojects and resources in place. Be sure to
configure your signing certificate before running on a real device.

You may want to place your *X-Com: UFO Defense* and/or *Terror from the Deep*
files into `Sources/OpenXcom/bin/UFO` and `Sources/OpenXcom/bin/TFTD`
respectively. This will copy the game data into the app bundle, which makes
running OpenXcom much easier. Note that this *will make the app bundle
non-redistributable*.

There are notes on the SDL upgrade, including what to do if you hit trouble, in
[`docs/sdl-upgrade-plan.md`](docs/sdl-upgrade-plan.md).

## Running the app on iOS

If you copied your *UFO Defense*/*TFTD* files into the bundle during the build
phase, that's probably everything you'd want. If not, you'll be greeted with an
error message upon running the app, and you'll have to copy your `UFO` and/or
`TFTD` folder from a working installation of OpenXcom onto the device.

Saved games are in the `xcom1` and `xcom2` folders, and should be compatible
with the desktop versions. Mods can be uploaded the same way; for big mods, use
OXCE's ziploader.

## Credits

This is a fork of [MeridianOXC/openxcom-ios](https://github.com/MeridianOXC/openxcom-ios),
which is itself a fork of sfalexrog's repository of OpenXcom for iOS — most of
the actual work on the iOS port was done by him, and the build system is
Meridian's.

The iPad input changes described above are mine only in the sense that I
directed and tested them; the code was written by Claude (Anthropic).
