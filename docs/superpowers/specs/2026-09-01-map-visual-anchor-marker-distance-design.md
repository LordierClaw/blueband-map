# Fixed Navigation Marker and Compact Guidance Visual Design

**Date:** 2026-09-01

## Goal

Improve the Smart Band 10 navigation presentation so the active route begins at the user marker, the user marker is a clean fixed navigation pointer, off-screen destinations sit closer to the curved edge, and distances use compact metre/kilometre labels.

## Observed problem

The hardware photo shows the bright active route offset from the user marker, a visually awkward concave marker, an off-screen destination ring that sits too far inside the display, and a raw metre value (`1354 m`) that consumes unnecessary header width.

The raster route is drawn through the Vietmap snapshot overlay projection, while the initial marker position is reconstructed through `VietmapSnapshotConfiguration.point(for:)`. The implementation must stop treating two projection paths as equivalent for the first published scene.

## Approved presentation

### User anchor and route

- Keep the user marker fixed at screen point `(106, 374)`: horizontally centred and approximately 72% down the 212x520 viewport.
- Keep the marker pointing straight up. Do not rotate among heading buckets during navigation.
- Rotate the map and route beneath the marker using the existing heading-up camera policy.
- Use the actual snapshot overlay projection as the authoritative presentation anchor for the rendered route and the first atomic marker publication.
- Begin the bright active route at that same authoritative anchor. The first published raster and marker must have zero pixel offset at their shared centre.
- Preserve existing course activation, heading hysteresis, rerouting, refresh throttling, and atomic scene publication. Do not increase raster refresh frequency merely to animate the fixed marker.
- During rerouting or failed refresh, preserve the previously confirmed raster; do not invent a bright connector from raw GPS to the old route.

### User marker

- Replace the current concave arrow with one clean upright triangular navigation pointer.
- Keep the existing 46x54 transparent resource canvas and safe-mask contract.
- Draw a dark outer triangle and a smaller bright green inner triangle with balanced margins.
- Generate only the single upright resource needed by the fixed presentation. Existing filenames may remain for compatibility, but every heading variant must render the same upright triangle until the protocol is simplified separately.

### Destination edge indicator

- Keep the visible destination pin unchanged.
- For `destinationMode=edge`, move the ring centre 6 pixels farther from the user anchor toward the physical display edge.
- The complete 20x20 ring must remain inside the physical curved-display contour. The 6-pixel movement consumes the existing conservative visual margin only for the edge indicator; it must not relax the user-marker or visible-destination safe-mask rules.
- Apply the same coordinate in `render.prepare.preview` and subsequent `nav.update` messages.

### Distance label

- Keep the wire value as non-negative integer metres.
- Format only on the Band:
  - below 1,000 metres: `<value> m`, for example `850 m`;
  - at least 1,000 metres: kilometres rounded to one decimal place, with a trailing `.0` removed, for example `1354 -> 1.4 km` and `2000 -> 2 km`;
  - arrived state: `ARRIVED`.
- Use one shared formatter for staged preview and live navigation updates.

## Protocol and safety boundaries

- Do not add fields or topics and do not change the 512-byte application envelope.
- Do not change verified Xiaomi BLE, SPP, authentication, encryption, ACK, or ThirdPartyApp bytes.
- Keep route-provider requests and navigation status semantics unchanged.
- Preserve complete preview validation and atomic raster/overlay promotion.

## Version and artifact policy

Both applications change in this release:

- IPA: bump `0.5.2 (18)` to `0.5.3 (19)`.
- RPK: bump `0.6.1 (16)` to `0.6.2 (17)`.

Merge completed work into `main`. Build the IPA only through GitHub Actions. Replace the old contents of `artifacts/handoff` with the current IPA and RPK, checksums, and handoff guide.

## Verification

### Automated

- Test that the authoritative snapshot anchor and active-route first point resolve to `(106, 374)` with zero pixel offset.
- Test cardinal and diagonal headings while the user marker remains upright and fixed.
- Test that all generated marker resources contain the approved identical upright triangle and transparent margin.
- Test edge destinations in all eight directions: each point is farther outward than the current conservative point and the complete ring remains within the physical contour.
- Test distance boundaries including `0`, `999`, `1000`, `1354`, `2000`, and a multi-digit kilometre value for both preview and live update paths.
- Run the canonical repository gates and GitHub iOS simulator/device build.

### Manual hardware acceptance

1. Start navigation while stationary and confirm the first bright route pixel meets the centre of the fixed upright marker.
2. Travel straight and through left/right turns; confirm the marker stays at `(106, 374)` pointing up while the map rotates beneath it.
3. Check destination indicators in several directions; confirm the ring sits visibly closer to the curved edge without clipping.
4. Check guidance around 999/1000 metres and beyond one kilometre; confirm compact `m`/`km` labels fit the header.
5. Trigger rerouting and a failed refresh; confirm no false connector appears and the previous confirmed map remains visible.

Compilation, deterministic tests, and artifact inspection do not establish Smart Band 10 hardware acceptance.
