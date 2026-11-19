# Testing on a real PT-P710BT

`ptouchkit-testpage` reads the printer's status and prints a 30 mm test page
encoded by PTouchKit, over USB or Bluetooth, through `PrinterClient` and the
transports in `PTouchKitTransports`. The page shows a frame, a short tick on the pin-0 edge, a
diagonal, a checker block, and **one bar** for the `.spec` quirk preset or **two
bars** for `.ptouch`.

## Bluetooth (macOS)

Pair the printer in System Settings → Bluetooth (PIN 0000 if asked). macOS only
lets a process use Bluetooth if the app that launched it declares
`NSBluetoothAlwaysUsageDescription`, so build the tool as an app bundle and launch
it with `open`:

```bash
Tools/hardware/make-testpage-app.sh
open -W --stdout "$PWD/testpage.log" --stderr "$PWD/testpage.log" .build/PTouchKitTestPage.app --args print --bluetooth
cat testpage.log
```

`--bluetooth` finds the paired printer; pass an address (`--bluetooth B4-22-00-ED-60-3B`)
to pick one. The tool opens RFCOMM channel 2 with IOBluetooth. Don't use the
`/dev/cu.*` serial port macOS creates: it opens channel 1, Apple's iAP2 channel,
which ignores raster commands. Disconnect phones and tablets first; the printer
takes one Bluetooth connection at a time.

## USB

Plug the printer in and turn it on. No driver or print queue is needed:

```bash
swift run ptouchkit-testpage status --usb
swift run ptouchkit-testpage print --usb --quirks spec
```

The tool opens the printer with IOUSBHost (bulk OUT endpoint 2, bulk IN endpoint 1).
`--out job.bin --tape 12` writes the job to a file instead.

## Other commands

- `ptouchkit-testpage list` shows a USB printer and paired Bluetooth printers
  (run it from the app bundle, since it touches Bluetooth).
- `ptouchkit-testpage status --hex "80 20 42 …"` decodes a status reply.

## What to record

- The raw status line: model code, width and type bytes for each tape you have.
- Whether each preset prints, and whether the bars, tick and checker look right.
- Status with the cover open, with no tape, and with a label made for a
  different width than the loaded tape.
