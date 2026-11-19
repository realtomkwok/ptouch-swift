# Golden fixtures

`generate.py` runs [ptouch](https://github.com/nbuchwitz/ptouch) as a black
box: it builds print jobs through ptouch's public API, captures every byte ptouch
would send to a PT-P710BT, and writes:

- `<name>.<i>.pbm` - the label bitmaps PTouchKit gets as input (P4; width =
  raster lines along the feed, height = print-area pins, 1 = black)
- `<name>.json` - media ID, job options and quirk preset
- `<name>.bin` - the exact bytes ptouch produced
- `index.json` - the fixture list and the ptouch version

into `Tests/PTouchKitTests/Fixtures/golden/`. The Swift tests encode each job
with PTouchKit and compare the bytes exactly.

## Regenerate

```bash
python3 -m venv .venv
.venv/bin/pip install -e reference/ptouch
.venv/bin/python Tools/golden/generate.py
```

Output is deterministic (seeded RNG). Regenerate after bumping the
`reference/ptouch` submodule and review the diff.

High-resolution fixtures: ptouch takes a 180 dpi image and repeats each raster
line; PTouchKit takes the bitmap at print resolution, so the PBM already has
every column doubled.
