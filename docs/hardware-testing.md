# Testing on a real PT-P710BT

`ptouchkit-testpage` reads the printer's status and prints a 30 mm test page
encoded by PTouchKit. The page shows a frame, a short tick on the pin-0 edge, a
diagonal, a checker block, and **one bar** for the `.spec` quirk preset or **two
bars** for `.ptouch`.

## Bluetooth (macOS)

1. Turn the printer on and pair it in System Settings → Bluetooth. macOS then
   creates a serial port, e.g. `/dev/cu.brothersPT-P710BLabelPr` (`ls /dev/cu.*`).
2. Read the status (prints nothing):

   ```bash
   swift run ptouchkit-testpage status --device /dev/cu.brothersPT-P710BLabelPr
   ```

3. Print with each preset and compare the labels:

   ```bash
   swift run ptouchkit-testpage print --device /dev/cu.brothersPT-P710BLabelPr --quirks spec
   swift run ptouchkit-testpage print --device /dev/cu.brothersPT-P710BLabelPr --quirks ptouch
   ```

The tool reads the loaded tape from the status reply, refuses to print if the
printer reports a problem, then prints each status the printer sends until
"printing completed".

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
