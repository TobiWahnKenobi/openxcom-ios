# Upgrading to SDL 2.32.x

Plan for replacing the vendored SDL 2.0.8 with current SDL2, so the three local
iOS patches (trackpad hover, secondary click, hardware keyboard) can be deleted
rather than maintained.

Everything below was verified against `libsdl-org/SDL` at `release-2.32.10`, not
recalled from memory.

---

## Target and why

- **`release-2.32.10`** — newest SDL2. Pin the tag, not a branch, so the build
  is reproducible.
- **Not SDL3.** Hard API break; OXCE is SDL2 throughout.

This is a **submodule replacement, not a version bump**. The submodule points at
`spurious/SDL-mirror`, a dead bot mirror of SDL's old Mercurial repo (last commit
2018). SDL now lives at `libsdl-org/SDL` with unrelated git history, so the old
SHA cannot be fetched from the new remote and the local SDL commits cannot be
rebased across. That is acceptable: the upgrade obsoletes all three of them.

### What upstream already provides

Verified present in `release-2.32.10`'s `src/video/uikit/SDL_uikitview.m`:

| Local patch | Upstream equivalent |
|---|---|
| Hover via `UIHoverGestureRecognizer` | `UIPointerInteraction` |
| Secondary click via `UIEvent.buttonMask` | same, **plus middle click** |
| Keyboard via `press.key.keyCode` | `scancodeFromPress:` |

Middle click on a real mouse is a genuine gain; UIKit exposes no tertiary mask
to the touch-based approach used locally.

---

## Phase 0 — Before touching anything

1. **Get the SDL work off this machine first.** The three SDL commits exist on
   no remote. Even though the upgrade makes them redundant, do not delete the
   only copy before the replacement is proven. Fork `spurious/SDL-mirror`, push
   `feature/ipados-trackpad-pointer` and `feature/ipados-hardware-keyboard`.
2. Tag the known-good state: `git -C Sources/OpenXcom tag pre-sdl-upgrade`, and
   note the outer commit.
3. Build and run once, so the baseline is known good rather than assumed.

## Phase 1 — Swap the submodule

```bash
git submodule deinit -f Sources/SDL
rm -rf .git/modules/Sources/SDL
git rm -f Sources/SDL
git submodule add https://github.com/libsdl-org/SDL Sources/SDL
git -C Sources/SDL checkout release-2.32.10
```

Editing the URL in `.gitmodules` is *not* enough — the histories are unrelated,
so git cannot fetch the recorded SHA from the new remote.

## Phase 2 — Rewire the Xcode project

Three changes, and the third is the lucky break:

| | Now | After |
|---|---|---|
| Subproject path | `Sources/SDL/Xcode-iOS/SDL/SDL.xcodeproj` | `Sources/SDL/Xcode/SDL/SDL.xcodeproj` |
| Target name | `libSDL-iOS` | `SDL2 (iOS)` |
| Product | `libSDL2.a` | `libSDL2.a` — **unchanged** |

Because the product name is identical, most link settings survive untouched.

**Expect new framework link errors.** Modern SDL's iOS target pulls in
frameworks 2.0.8 did not: `Metal` and `CoreHaptics` (both weak-linked),
`GameController`, `QuartzCore`. Add them to the Game target as the linker asks.

Do this in Xcode's UI rather than hand-editing `project.pbxproj`. That file is
held under `skip-worktree`; commit the result with:

```bash
scripts/commit-xcodeproj.sh "Point the SDL subproject at Xcode/SDL and link new frameworks"
```

which strips the local signing identity, commits, and restores it. Run it with
`--check` first to see the diff without committing.

## Phase 3 — Fix the compile break

`SDL_HINT_ANDROID_SEPARATE_MOUSE_AND_TOUCH` **was removed** — it is absent from
2.32's `SDL_hints.h`, so this is a hard compile error, not a deprecation
warning. Two call sites:

- `src/Menu/OptionsSystemState.cpp:235`
- `src/Menu/VideoState.cpp:546`

Replace with `SDL_HINT_MOUSE_TOUCH_EVENTS` / `SDL_HINT_TOUCH_MOUSE_EVENTS`.

Nothing else in OXCE's SDL surface changed. It uses only `SDL_CreateRenderer`,
`SDL_RenderCopy`, `SDL_RenderClear`, `SDL_RenderPresent`, `SDL_RenderReadPixels`,
`SDL_CreateTexture`, `SDL_GetRendererOutputSize` and `SDL_RendererInfo`, all
stable across SDL2's lifetime.

## Phase 4 — The behavioural landmine

**On mobile, `SDL_HINT_MOUSE_TOUCH_EVENTS` defaults to `"1"`** — mouse input
also generates synthetic *touch* events. OXCE's finger path in `Game.cpp` would
then fire on trackpad clicks **in addition to** the real mouse events, double
handling every click and confusing the battlescape gesture state machine.

Set it to `"0"` at startup, unconditionally. There is no case where OXCE wants
it on: it reads mouse and finger events separately and filters
`SDL_TOUCH_MOUSEID` itself. With no pointer attached the hint is simply inert,
so nothing needs detecting.

This will not show up as a build failure. It is the single most likely runtime
regression of the whole upgrade.

## Phase 5 — Delete what is now redundant

Drop all three SDL patches (see table above).

**Keep every OXCE-side change** — none of them are SDL-version dependent:

- letterbox cursor mapping (`Screen.cpp`)
- points→pixels for real pointer events (`Game.cpp`)
- `getPointerState` returning renderer pixels (`CrossPlatform.cpp`)
- the battlescape gesture scheme
- `UIApplicationSupportsIndirectInputEvents` in `OpenXcom-Info.plist` — this is
  a **prerequisite** for SDL's `UIPointerInteraction` path to receive anything
  at all, not an optional extra

## Phase 6 — Verify on device

A clean build proves very little here. Check in this order and stop at the first
failure:

1. Launches, menu renders, letterbox geometry still reports `7.375 / 7.375`
2. Touch: tap, one-finger pan, two-finger tap and hold — the gesture machine is
   the most exposed to the hint changes in Phase 4
3. Trackpad: hover, left, right, **middle** (new)
4. Keyboard: a hotkey, a Ctrl-click, and naming a soldier — the last one checks
   that text input is not double-entered
5. Audio and music — SDL_mixer compiled against newer SDL2 headers
6. Save, load, and a battlescape mission end to end

## Phase 7 — Leave the siblings alone

`SDL_image`, `SDL_mixer` and `SDL_gfx` stay at their current versions. SDL2 is
API-stable, they compile against whatever SDL2 headers are on the include path,
and that path does not change. Upgrade them only if something actually breaks —
bundling it in makes any failure impossible to attribute.

---

## Effort, risk and bail-out

Realistically **a day**, concentrated in Phase 2 and Phase 6 rather than in
code. Roughly two thirds of the risk is Xcode project surgery.

Bail out if Phase 2 becomes a rabbit hole of link errors. The current build
works; the upgrade buys deletion of three patches and middle-click support, and
neither is urgent. Rollback: restore the outer commit and re-add the old
submodule.

## Worth doing once it works

- **arm64 simulator.** The build is pinned to x86_64, which is why it runs under
  Rosetta and why `-destination 'platform=iOS Simulator,name=…'` fails to match
  (use `id=<udid>`). Modern SDL supports arm64 simulator.
- **`SDL_RenderWindowToLogical`** (2.0.18+) is the proper replacement for the
  manual points→pixels arithmetic in `Game.cpp` and `CrossPlatform.cpp`.
- **`Options::fakeEvents`**, the lost-`fingerUp` workaround, is probably
  obsolete. Test before removing.
- **Pointer presence detection** via `GCMouse` (GameController, iOS 14+) with
  `GCMouseDidConnect` / `GCMouseDidDisconnect`, to hide the on-screen touch
  button bar while a mouse or trackpad is attached and bring it back when it is
  removed. This needs a small Objective-C helper in the app target; it does not
  require patching SDL.
