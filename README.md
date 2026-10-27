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

## Install automatic startup and temperature access

Run this as your normal logged-in user (do not put sudo before it):

```sh
bash scripts/install.sh
```

Enter your administrator password when sudo asks. The installer builds the app,
installs it at `/Applications/MacStats.app`, starts it immediately, and installs:

- A user LaunchAgent, `~/Library/LaunchAgents/local.macstats.app.plist`, which starts
  the menu bar app at login and restarts it after a crash. Choosing Quit keeps it
  closed until the next login.
- A root LaunchDaemon, `/Library/LaunchDaemons/local.macstats.temperature.plist`,
  which runs a fixed, root-owned temperature collector every ten seconds. Only
  this collector runs with elevated privileges; the app runs as your normal user.

The collector runs `/usr/bin/powermetrics --samplers smc -i 1000 -n 1` and atomically
replaces `/Library/Application Support/MacStats/temperature.txt`. Output is bounded
to one sample; the app rejects readings older than 35 seconds. The collector runs
at system startup, including when no user is logged in. No passwords are stored
and no passwordless sudo rule is added. This local installation uses launchd
rather than requiring a Developer ID certificate and an SMAppService helper.

Allow MacStats background activity if macOS asks. Do not add a separate Open at
Login entry: the installer already creates the login job. If you previously
added MacStats manually, remove that entry to avoid launching duplicate copies.
Log out and back in to verify startup; allow about 20 seconds for temperatures.

Re-run the installer after source changes. It replaces the installed build and
restarts both jobs. To inspect the jobs and the latest reading:

```sh
launchctl print "gui/$(id -u)/local.macstats.app"
sudo launchctl print system/local.macstats.temperature
cat '/Library/Application Support/MacStats/temperature.txt'
```

To remove the installed app, login job, and privileged collector:

```sh
bash scripts/uninstall.sh
```

Your source checkout is preserved. A reboot/login test and live temperature
verification require completing the administrator-authorized installation.
