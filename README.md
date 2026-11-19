# PTouchKit

A platform-independent Swift package for the Brother PT-P710BT label printer
(and its PT-E550W/P750W siblings). It builds the raster print job and parses
printer status. It uses Foundation only, so it builds on Linux as well as on
Apple platforms. Transports (USB, Bluetooth, network) are supplied by the host.

Status: early. The package itself doesn't exist yet.

## How it's written

PTouchKit is written from Brother's public *Raster Command Reference* for the
PT-E550W/P750W/P710BT (`cv_pte550wp750wp710bt_eng_raster_102.pdf`). Code
cites the spec section it implements.

The [`ptouch`](https://github.com/nbuchwitz/ptouch) Python library
(LGPL-2.1-or-later) is used only as a black-box test oracle: `Tools/golden/`
runs it to produce expected bytes, and the tests compare PTouchKit's output
against them byte for byte. Don't copy ptouch's code or structure into
PTouchKit. `reference/ptouch` is a read-only git submodule; never edit it.

## Layout

- `Package.swift`, `Sources/`, `Tests/` - the PTouchKit package (coming)
- `Tools/golden/` - generates golden fixtures from `ptouch`
- `docs/protocol/` - P710BT raster protocol notes
- `reference/ptouch/` - git submodule: upstream Python library (read-only)

Clone with `git clone --recurse-submodules`.

## Licence

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

P-touch is a trademark of Brother Industries; this project isn't affiliated
with Brother.
