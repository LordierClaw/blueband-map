# Band Overlay Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the malformed Band navigation overlays with symmetric RGBA icons and a visible native header panel while freezing route behavior.

**Architecture:** Reuse the existing generated-asset and `<image>` overlay path. Make the marker and edge chevrons deterministic RGBA PNGs, replace the shade image with one native div, and enforce the packaged result with behavioral tests.

**Tech Stack:** Node.js standard library, Vela Quick App UX/CSS, `node:test`, Docker/Make.

---

### Task 1: Lock the failing overlay contracts

**Files:**
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/test/envelope-page.test.mjs`

- [ ] **Step 1: Replace the false marker invariant with an exact RGBA mirror assertion**

Decode filter-0 RGBA rows and assert every pixel at `(x, y)` equals `(45 - x, y)`, that marker PNG colour type is `6`, and that all eight marker files are byte-identical.

- [ ] **Step 2: Require clean larger RGBA edge chevrons**

Assert every `destination-edge-N.png` is 34×34 RGBA, contains amber strokes without the former light tip-dot colour, and reaches the appropriate outward edge.

- [ ] **Step 3: Require the native panel and new edge positioning**

Assert the page contains `nav-panel`, no longer references `nav-shade.png`, defines an explicit background and shadow, and returns edge style `left:<x-17>px;top:<y-17>px;width:34px;height:34px;`.

- [ ] **Step 4: Run the focused tests and observe RED**

Run:

```bash
docker compose run --rm node-rpk bash -lc 'npm ci >/dev/null && node --test --test-concurrency=1 test/bundle-contract.test.mjs test/envelope-page.test.mjs'
```

Expected: failures for indexed marker assets, 28×28 decorated edge assets, the shade image, and old positioning.

### Task 2: Generate deterministic RGBA overlay assets

**Files:**
- Modify: `apps/band/scripts/generate-icon.mjs`
- Delete: `apps/band/src/common/nav-shade.png`
- Regenerate: `apps/band/src/common/marker-0.png` through `marker-7.png`
- Regenerate: `apps/band/src/common/destination-edge-0.png` through `destination-edge-7.png`

- [ ] **Step 1: Generalize the existing filter-0 RGBA PNG writer**

Add a small `rgbaPNG(width, height, pixels)`/`writeRGBA(...)` helper using the existing `chunk`, `crc32`, and `deflateSync` functions. Do not add a package.

- [ ] **Step 2: Paint the approved symmetric pointer**

Use paired spans around the half-pixel axis so every row uses endpoints whose sum is `45`. Paint a white outer closed triangle and a green inner closed triangle into a transparent 46×54 RGBA bitmap; write the same bytes to all eight marker names.

- [ ] **Step 3: Paint eight clean chevrons**

Draw only two outlined line segments per 34×34 bitmap, rotate their points offline, and omit the old filled polygon and tip dot.

- [ ] **Step 4: Regenerate assets and rerun the focused tests**

Run:

```bash
docker compose run --rm node-rpk bash -lc 'npm run generate:icon && node --test --test-concurrency=1 test/bundle-contract.test.mjs test/envelope-page.test.mjs'
```

Expected: asset assertions pass; page assertions remain red until Task 3.

### Task 3: Replace the shade with the native panel

**Files:**
- Modify: `apps/band/src/pages/index/index.ux`
- Modify: `apps/band/scripts/verify-rpk.mjs`

- [ ] **Step 1: Replace the shade image**

Insert `<div class="nav-panel" ...></div>` before `nav-header`; remove the `nav-shade` image and CSS.

- [ ] **Step 2: Add visible native styling**

Use an inset 198×88 dark panel with rounded corners, a contrasting border, and a black shadow. Leave header child positions unchanged.

- [ ] **Step 3: Centre the larger edge asset**

Change edge overlay positioning from 14-pixel offsets to 17-pixel offsets and include explicit 34×34 inline dimensions. Leave visible destination-pin behavior unchanged.

- [ ] **Step 4: Update RPK verification**

Remove `common/nav-shade.png` from required entries and reject it if present. Verify marker and edge resources inside the RPK are RGBA and have the expected dimensions.

- [ ] **Step 5: Run Band tests**

Run `make test-rpk`.

Expected: 27 or more tests pass and the normal build verifies one RPK.

### Task 4: Version, package, and verify

**Files:**
- Modify: `apps/band/src/manifest.json`
- Modify: `apps/band/package.json`
- Modify: `apps/band/test/bundle-contract.test.mjs`
- Modify: `apps/band/scripts/verify-rpk.mjs`
- Modify: `apps/band/src/pages/index/index.ux`
- Replace: `artifacts/handoff/*.rpk`

- [ ] **Step 1: Bump only RPK**

Set version name to `0.6.6`, version code to `21`, and visible RPK labels/build expectations to `0.6.6`. Do not change the iOS version.

- [ ] **Step 2: Run canonical verification**

Run:

```bash
make test
make lint
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 3: Inspect the produced RPK**

Confirm its manifest is `0.6.6 (21)`, shade is absent, marker assets are 46×54 RGBA, destination edge assets are 34×34 RGBA, and packaged asset bytes equal source bytes.

- [ ] **Step 4: Replace the handoff RPK**

Delete the older handoff RPK and copy the newly verified `0.6.6` RPK into `artifacts/handoff`; retain the unchanged current IPA.

- [ ] **Step 5: Commit and push main**

Commit the tested source, documentation, and generated assets, then push `main` to `origin/main`. Do not commit ignored handoff binaries.
