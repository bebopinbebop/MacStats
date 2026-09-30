# MacStats

A tiny native macOS menu bar monitor for CPU, memory, thermal state, and best-effort SMC temperature readings.

## Run

```sh
swift run MacStats
```

The app runs as an accessory menu bar app, so it does not appear in the Dock. Use the status item menu to copy a snapshot or quit.

## Build

```sh
swift build -c release
```

The release binary will be at:

```text
.build/release/MacStats
```

To create a clickable menu bar app bundle:

```sh
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

Then open:

```text
dist/MacStats.app
```

## Notes

CPU and memory refresh every second. Temperature refreshes every 10 seconds because `powermetrics` is heavier than the lightweight CPU/RAM calls.

Temperature uses `/usr/bin/powermetrics --samplers smc -n 1` first, then falls back to direct AppleSMC sensor reads. `powermetrics` usually requires root, so a normal double-click launch may show temperature as unavailable unless the app has permission to run that command. CPU, memory, and thermal state continue to work either way.
