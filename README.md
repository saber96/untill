# Untill

Untill is a native macOS 14+ menu bar utility. Build it on a Mac with the Xcode command-line tools.

```sh
./build.sh
open build/Untill.app
```

The app opens Permissions on first launch. Grant Accessibility for the global trigger and app actions, Screen Recording for screenshots, and Microphone for voice memos. The Permissions tab also offers Input Monitoring when the system reports that access is missing. Keep the app in a stable location so macOS can associate permissions with it. For a stable signing identity across rebuilds, set `UNTILL_SIGN_IDENTITY` to a local code-signing identity before building.

## Controls

- Hold Option–Space, move toward a tool, then release to run it. Releasing in the center cancels.
- Tap Option–Space to leave the wheel open. Click a tool, press 1–8, or use the arrows and Return. Esc or another tap dismisses it.
- Press Tab to switch rings, or scroll down for ring 2 and up for ring 1.
- Push past Volume and move inward or outward to change the preview. Release or click to apply. With the keyboard, select Volume, adjust with the arrows, and press Return to apply.
- Open Settings from the menu bar icon to record a modified keyboard shortcut, assign a mouse button, toggle tools, or move tools within and between rings.

The first ring starts with Copy, Paste, Cut, Plain Paste, Undo, Redo, Select All, and Spotlight. The second starts with Tile Left, Tile Right, Fill Screen, Screenshot, Voice Memo, Play/Pause, Next Track, and Volume. Screenshot copies the selected area or current display to the clipboard and shows a thumbnail confirmation. Paste with Command–V in an app that accepts images. Voice Memo starts recording on the first selection and stops on the next, saving to `~/Music/Untill Voice Memos`.


## Capture and utilities

- **Screenshot** defaults to **Select area**. Run it from the ring, then drag on the display where the ring opened. Esc cancels. Set **Screenshot mode** in Settings → Controls to **Entire display** for full-display capture. To give area capture its own slot, add **Screenshot Area** in Settings → Tools → Choose Tool.
- In Settings → Tools, use **Choose Tool** beside any slot to swap in Pinned Apps, Music, Clipboard, Notes, Timers, or Ask AI. The switch and arrow buttons enable, disable, and reorder tools across both rings.
- **Pinned Apps** remembers the apps you add. **Music** provides previous, play/pause, and next for the current system media player.
- **Clipboard** displays plain text and offers an optional history of the last 15 entries for the current session. **Notes** saves one editable note locally.
- **Timers** runs multiple countdowns while Untill is open, with a sound and on-screen confirmation at completion.
- **Ask AI** copies the prompt and opens ChatGPT. Paste and send the prompt when ready.
- Set **Wheel look** in Settings → Controls to Glass, Graphite, or Paper.

## Tests and diagnostics

Run `./test.sh` for automated checks of wheel geometry, screenshot selection bounds, shortcut validation, preference persistence and migration, text validation, and timer limits and expiration. The tests use a separate preferences suite and do not send keyboard or pointer events.

Watch Untill's errors in Terminal while reproducing an issue:

```sh
log stream --level info --predicate 'subsystem == "com.untill.radial"'
```

The lifecycle, input, capture, and tools categories log failures and relevant system error codes. Logs exclude clipboard contents, note text, prompts, screenshots, and pinned-app paths.

### Desktop regression checklist

Use a disposable document and clipboard. Start with the current signed app and grant permissions through its Permissions tab. Verify which app is running before testing a rebuild.

| Surface | Actions and expected results |
| --- | --- |
| Menu bar | Open Settings and Permissions, verify the correct tab opens, then use Quit and relaunch. |
| Controls | Record a modified shortcut, tap and hold it, then Reset. Try an unmodified key and an unsupported key and check for the inline error. Press Esc during recording. Try Off and each available mouse trigger, all three wheel looks, and both screenshot modes. |
| Tools | Toggle a slot off and confirm mouse and keyboard activation skip it. Toggle it on, swap it with Choose Tool, move it up and down including across rings, and reopen the app to confirm settings persist. Confirm the first and last move controls are disabled when appropriate. |
| Permissions | Follow each Grant Access button. Verify the status after returning from System Settings and after reopening Untill. Check the missing-permission path for Screenshot and Voice Memo if testing without access. |
| Wheel | Tap to keep open, hold and release to commit, press Tab or scroll across both rings, test 1–8 and arrow keys with Return, and dismiss with Esc or an outside click. Try a second display, a screen edge, and a full-screen Space. |
| Editing and windows | In the disposable document, exercise Copy, Paste, Cut, Plain Paste, Undo, Redo, Select All, and Spotlight. Test Plain Paste with a non-text clipboard and test all tiling actions with and without a focused window. |
| Screenshots | Capture an entire display, a normal area, and a reverse drag. Try a click, a drag smaller than two points, and Esc. Confirm a preview and an image on the clipboard only after a valid capture. |
| Audio | Start and stop Voice Memo and verify the saved recording. With a media player active, use Play / Pause, Next Track, the Music panel's three buttons, and the Volume slider. Check the unsupported-output path if available. |
| Pinned Apps | Open the picker and cancel, try choosing a non-app, add an app twice, launch it, and unpin it. |
| Clipboard | Verify current text and the empty state. Toggle history, copy several disposable strings, restore one, clear history, and toggle it off. |
| Notes and Ask AI | Enter only whitespace and verify Copy stays disabled. Try ordinary text, copy the note, relaunch to verify it persists, and use Copy Prompt and Open ChatGPT with a test prompt. |
| Timers | Use both stepper controls, start a timer, cancel a second timer, and wait for the first timer to show its alert. |
