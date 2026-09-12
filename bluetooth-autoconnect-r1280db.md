# Auto-Connecting a Bluetooth Device on Boot (Fedora + BlueZ)

**Device:** Edifier R1280DB speakers
**MAC address:** `5C:C6:E9:8D:29:D7`
**System:** Fedora 44, BlueZ (`bluetoothd`), systemd user services

## The problem

Once a Bluetooth device is paired and trusted, most people assume Linux will
reconnect to it automatically on every boot. It doesn't — at least not
reliably.

BlueZ *does* have a reconnect policy (`[Policy]` section in
`/etc/bluetooth/main.conf`, keys `ReconnectUUIDs` / `ReconnectAttempts` /
`ReconnectIntervals`), but it only kicks in on **link loss** — e.g. the
device drops out of range, or the machine suspends and resumes. It does
**not** retry connecting to a previously-paired device after a **cold boot**,
because from BlueZ's point of view there was no active connection to lose in
the first place.

So even though the adapter powers on automatically at boot
(`AutoEnable=true`, the BlueZ default) and the device is already paired,
bonded, and trusted, nothing ever issues the actual `connect` call — you have
to do it manually every time.

## The fix

A small systemd **user** service that retries `bluetoothctl connect <MAC>`
for a couple of minutes after login. This is long enough to cover the time
it takes to physically power on the speakers, and it exits early as soon as
the connection succeeds.

### 1. The retry script

`~/.local/bin/bt-autoconnect.sh`:

```bash
#!/bin/bash
# Retry-connect a Bluetooth device at login, since BlueZ only auto-reconnects
# on link loss (suspend/resume), not on a fresh boot.
MAC="${1:?usage: bt-autoconnect.sh AA:BB:CC:DD:EE:FF}"
ATTEMPTS=20
INTERVAL=5

for i in $(seq 1 "$ATTEMPTS"); do
    if bluetoothctl info "$MAC" | grep -q "Connected: yes"; then
        exit 0
    fi
    bluetoothctl connect "$MAC" >/dev/null 2>&1
    sleep "$INTERVAL"
done

exit 1
```

Made executable with `chmod +x`. It takes the device's MAC address as an
argument, which keeps it reusable for any other Bluetooth device.

### 2. The systemd template unit

`~/.config/systemd/user/bt-autoconnect@.service`:

```ini
[Unit]
Description=Auto-connect Bluetooth device %i
After=bluetooth.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/bt-autoconnect.sh %i

[Install]
WantedBy=graphical-session.target
```

This is a systemd **template** unit (note the `@` before `.service`). The
`%i` placeholder is filled in with whatever instance name you enable it
with — in this case the device's MAC address — so `%i` becomes the argument
passed to the script, and also shows up in `systemctl status` for easy
identification.

- `After=bluetooth.target` — waits until the Bluetooth stack is up before
  trying to connect.
- `Type=oneshot` — runs once, then exits; not a long-running daemon.
- `WantedBy=graphical-session.target` — starts on every actual GNOME
  login/logout cycle. **Do not use `default.target` here** — that target
  belongs to `user@<uid>.service`, the per-user systemd manager, which
  starts once and then stays running across multiple GNOME logout/login
  cycles as long as anything else (a terminal, an SSH session, another
  process) holds a session open for your user. A oneshot unit
  `WantedBy=default.target` therefore only fires once per that manager's
  lifetime — effectively once per boot in practice — not on every desktop
  logout/login, even though `enable --now` and a fresh boot both look like
  they work. `graphical-session.target` is the target gnome-session itself
  starts and stops on every real login/logout, independent of whether the
  user manager stays resident, so it's the correct target for
  "run this each time I log into the desktop."

Using a **user** service (rather than a system-wide one) means it runs in
your session with access to your D-Bus session bus, which is what
`bluetoothctl` needs — no `sudo` required.

### 3. Enabling it for a specific device

```bash
systemctl --user daemon-reload
systemctl --user enable --now 'bt-autoconnect@5C:C6:E9:8D:29:D7.service'
```

(If you're migrating an existing instance off `default.target`, run
`systemctl --user disable` first so the old `default.target.wants` symlink
is removed before re-enabling under the new target.)

`enable` creates the symlink so it starts on every future login;
`--now` also starts it immediately for the current session.

### 4. Verifying it worked

```bash
bluetoothctl info 5C:C6:E9:8D:29:D7 | grep Connected
# Connected: yes

systemctl --user status 'bt-autoconnect@5C:C6:E9:8D:29:D7.service'
```

A finished one-shot service shows as `inactive (dead)` with
`status=0/SUCCESS` in the log — that's the expected, successful end state,
not a failure.

## Reusing this for another device

Because the unit is a template and the script takes the MAC as a parameter,
adding another device (e.g. a mouse, headphones) needs no new files — just:

```bash
bluetoothctl paired-devices          # find the MAC address
systemctl --user enable --now 'bt-autoconnect@<MAC>.service'
```

## Troubleshooting

- **Still not connecting:** confirm the device is actually paired, bonded,
  and trusted first — `bluetoothctl info <MAC>`. This whole approach assumes
  pairing is already done; it only automates the reconnect step.
- **Adapter not powered at boot:** check `bluetoothctl show` for
  `Powered: yes`. If it's `no`, uncomment `AutoEnable=true` under
  `[Policy]` in `/etc/bluetooth/main.conf` and restart
  `bluetooth.service`.
- **Service runs but times out:** increase `ATTEMPTS`/`INTERVAL` in the
  script if the device is slow to power on or advertise.
- **Check logs:** `journalctl --user -u 'bt-autoconnect@*.service'`
