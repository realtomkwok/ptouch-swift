# Testing on a real PT-P710BT

`ptouchkit-testpage` reads the printer's status and prints a 30 mm test page
encoded by PTouchKit. It works over USB today. The page shows a frame, a short tick on the pin-0 edge, a
diagonal, a checker block, and **one bar** for the `.spec` quirk preset or **two
bars** for `.ptouch`.

## Bluetooth (macOS)

Not yet. The serial port macOS creates after pairing
(`/dev/cu.brothersPT-P710BLabelPr`) talks to RFCOMM channel 1, which is Apple's iAP2
accessory channel, so the printer never answers there. Printing over Bluetooth
needs IOBluetooth on channel 2 (see `docs/protocol/README.md`); the test-page tool
will gain that with the macOS transports.

## USB

Write the job to a file and send it raw through a CUPS queue for the printer:

```bash
swift run ptouchkit-testpage print --out job.bin --tape 12 --quirks spec
lpstat -v            # find the queue name
lp -d <queue> -o raw job.bin
```

USB gives no status reply this way.

## What to record (ITS-53)

- The raw status line: model code, width and type bytes for each tape you have.
- Whether each preset prints, and whether the bars, tick and checker look right.
- Status with the cover open, with no tape, and with a label made for a
  different width than the loaded tape.
