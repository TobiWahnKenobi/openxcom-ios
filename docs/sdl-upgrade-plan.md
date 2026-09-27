# Upgrading SDL: 2.0.8 → 2.32.10

**Status: done.** Completed 2026-09-27. This was written as a plan, then
corrected against what actually happened, so it can be followed again for a
future SDL bump or on another machine.

The goal was to delete three locally maintained iOS patches (trackpad hover,
secondary click, hardware keyboard) by moving to an SDL that has them upstream.

---

## Outcome

| | |
|---|---|
| SDL | `libsdl-org/SDL` at `release-2.32.10` |
| OpenXcom source changes needed | **one line** — a hint (see Phase 4) |
| Translation units recompiled unchanged | ~500 |
| Local SDL patches deleted | 3 |
| Gained | middle click on a real mouse |

Eight years of SDL required no source changes to OpenXcom. The whole job was
subproject wiring, one framework, and one hint.

Verified in the built binary: it exports upstream's
`pointerInteraction:regionForRequest:defaultRegion:` and `scancodeFromPress:`,
and none of the local patch selectors survive.

| Local patch (deleted) | Upstream equivalent |
|---|---|
| Hover via `UIHoverGestureRecognizer` | `UIPointerInteraction` |
| Secondary click via `UIEvent.buttonMask` | same, **plus middle click** |
| Keyboard via `press.key.keyCode` | `scancodeFromPress:` |

---

## Phase 0 — Prerequisites

**Install the Metal Toolchain first.** This was missing from the original plan
and is the first thing that fails:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Xcode 26 ships `metal` as a stub that errors with *"cannot execute tool 'metal'
due to missing Metal Toolchain"*. SDL 2.32's iOS static library target compiles
`src/render/metal/SDL_shaders_metal.metal`; SDL 2.0.8's old iOS project never
did, which is why this never came up before. 705 MB, and it does **not** need
admin rights.

Also: get any local SDL work onto a remote before starting, tag the good state
(`git tag pre-sdl-upgrade`), and confirm the current build works so the baseline
is known rather than assumed.

## Phase 1 — Replace the submodule

A URL edit is not enough. `spurious/SDL-mirror` is a dead bot mirror of SDL's
old Mercurial repo (last commit 2018); `libsdl-org/SDL` has unrelated history,
so the recorded SHA cannot be fetched from it.

```bash
git submodule deinit -f Sources/SDL
rm -rf .git/modules/Sources/SDL
git rm -f Sources/SDL
git submodule add https://github.com/libsdl-org/SDL Sources/SDL
git -C Sources/SDL checkout release-2.32.10
```

Stay on SDL2. SDL3 is a hard API break and OXCE is SDL2 throughout.

## Phase 2 — Rewire the Xcode project

| | Before | After |
|---|---|---|
| Subproject path | `Sources/SDL/Xcode-iOS/SDL/SDL.xcodeproj` | `Sources/SDL/Xcode/SDL/SDL.xcodeproj` |
| Target name | `libSDL-iOS` | **`Static Library-iOS`** |
| Target uuid | `FD6526620DE8FCCB002AD96B` | `A7D88D1723E24D3B00DCD162` |
| Product ref uuid | `FD6526630DE8FCCB002AD96B` | `A7D88E5423E24D3B00DCD162` |
| Product | `libSDL2.a` | `libSDL2.a` — unchanged |

The product name not changing is why the link settings survive.

Both `PBXContainerItemProxy` entries need updating: `proxyType = 1` is the
target dependency, `proxyType = 2` is the product reference. `remoteInfo` on
both becomes `Static Library-iOS`.

**Link `CoreHaptics`.** SDL 2.32 uses `CHHaptic*` for controller rumble, and a
static library carries no framework dependencies, so the app must link it. It
was added as `OTHER_LDFLAGS = ("-framework", CoreHaptics)` rather than a build
phase entry — one setting, no PBX UUID forging. Nothing else was missing; the
rest of SDL's framework list is for its macOS targets.

Commit this file with:

```bash
scripts/commit-xcodeproj.sh "…"        # --check to preview
```

It strips the local signing identity, commits, and restores it.

## Phase 3 — Compile breaks: none

The original plan predicted `SDL_HINT_ANDROID_SEPARATE_MOUSE_AND_TOUCH` (removed
in modern SDL) would be a hard error at `OptionsSystemState.cpp:235` and
`VideoState.cpp:546`. **It is not.** Both sit inside `#ifdef __ANDROID__`, which
this target never defines — iOS defines only `__MOBILE__`. They would break an
Android build, but that is not this repo.

Nothing else in OXCE's SDL surface changed. It uses only `SDL_CreateRenderer`,
`SDL_RenderCopy`, `SDL_RenderClear`, `SDL_RenderPresent`, `SDL_RenderReadPixels`,
`SDL_CreateTexture`, `SDL_GetRendererOutputSize` and `SDL_RendererInfo`, all
stable across SDL2's lifetime.

## Phase 4 — The one real code change

`SDL_HINT_MOUSE_TOUCH_EVENTS` defaults to `"1"` on mobile, so a real mouse or
trackpad **also** raises synthetic touch events. The finger path in `Game::run`
would then handle every trackpad click a second time, on top of the mouse events
it already gets, and confuse the battlescape gesture state machine.

Set before `SDL_Init` in `Game.cpp`:

```cpp
#if defined(__MOBILE__) && defined(SDL_HINT_MOUSE_TOUCH_EVENTS)
	SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
#endif
```

Guarded on the macro so it still compiles against 2.0.8, which predates the
hint — the change survives a rollback. No detection is needed: OXCE never wants
the synthetic events, and with no pointer attached the hint is inert.

This produces no build failure. It is the only silent regression risk.

## Phase 5 — Keep the OXCE-side work

None of it is SDL-version dependent:

- letterbox cursor mapping (`Screen.cpp`)
- points→pixels for real pointer events (`Game.cpp`)
- `getPointerState` returning renderer pixels (`CrossPlatform.cpp`)
- the battlescape gesture scheme
- `UIApplicationSupportsIndirectInputEvents` in `OpenXcom-Info.plist` — a
  **prerequisite** for SDL's `UIPointerInteraction` path to receive anything

## Phase 6 — Verify on device

A clean build proves very little. In order, stopping at the first failure:

1. Launches, menu renders, letterbox geometry symmetric
   (on iPad Pro 13" this reads `scaleX = scaleY = 8.6`, band 172)
2. Touch: tap, one-finger pan, two-finger tap and hold — most exposed to Phase 4
3. Trackpad: hover, left, right, **middle** (new)
4. Keyboard: a hotkey, a Ctrl-click, and naming a soldier (checks text input is
   not double-entered)
5. Audio and music — SDL_mixer against newer SDL2 headers
6. Save, load, a battlescape mission end to end

Simulator smoke-testing covered 1 only. Touch and pointer input cannot be
injected from a shell here.

## Phase 7 — Siblings untouched

`SDL_image`, `SDL_mixer` and `SDL_gfx` stayed at their existing versions and
needed no changes. SDL2 is API-stable and they compile against whatever SDL2
headers are on the include path.

---

## Still worth doing

- **arm64 simulator.** The build is pinned to x86_64, so it runs under Rosetta,
  and `-destination 'platform=iOS Simulator,name=…'` fails to match — use
  `id=<udid>`. Modern SDL supports arm64 simulator.
- **`SDL_RenderWindowToLogical`** (2.0.18+) properly replaces the manual
  points→pixels arithmetic in `Game.cpp` and `CrossPlatform.cpp`.
- **`Options::fakeEvents`**, the lost-`fingerUp` workaround, is probably
  obsolete now. Test before removing.
- **Pointer presence detection** via `GCMouse` (GameController, iOS 14+) with
  `GCMouseDidConnect` / `GCMouseDidDisconnect`, to hide the on-screen touch
  button bar while a mouse or trackpad is attached. Needs a small Objective-C
  helper in the app target; does not require patching SDL.
