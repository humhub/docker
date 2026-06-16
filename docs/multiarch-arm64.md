# Multiarch (amd64 + arm64) Rollout

Working notes for adding `linux/arm64` support to the HumHub Docker image.

## Insights

- Both base images already ship arm64 variants: `debian:bookworm` and `dunglas/frankenphp:1-php8.4`. No image swaps needed.
- Plain `docker build` cannot produce multi-arch manifests — `docker buildx` via `docker/build-push-action@v6` is required.
- Three files change; dispatcher workflows (`*-dispatcher.yml`) need no changes:
  - `image/Dockerfile` — add `--platform=$BUILDPLATFORM` to the **builder** stage only (runtime stage stays unpinned) so asset compilation runs natively instead of under QEMU.
  - `.github/workflows/docker-publish-nightly.yml`
  - `.github/workflows/docker-publish-release.yml`
- Branch-name gating is **not** rotation-proof: a gate keyed on `develop`/`main` is evaluated at runtime by branch name, but code rotates while the names stay put. Use it only for nightly; use **version gating** for releases.
- **Automated (cron) nightly runs from `main`.** The cron dispatcher fires from the default branch and calls the inner workflow via a local `uses: ./...` ref, so GitHub resolves the **workflow steps from `main`**, regardless of the matrix `ref`. Only the **build context** (`Dockerfile`, `image/*`) is checked out from the `ref` input. Therefore develop-only changes to the workflow *steps* do **not** affect the automated nightly until rotation carries them to main. The arm64 *image* for v1.18 stays off via the gate either way.
- **Rolling channel tags must not be moved by partial builds.** The rolling tag (`experimental-nightly`) and the immutable `…-<ts>-<sha>` tag are pushed on every run. A manual run that narrows the platform set (amd64-only or arm64-only) would otherwise overwrite the shared `experimental-nightly` with a single-arch image — breaking `docker pull` for the other arch. Guard: only push the rolling tag when the resolved platform set equals the ref's **canonical** set (develop → both); narrowed manual runs publish the immutable tag only.
- **Pre-rotation, multiarch `experimental-nightly` is not durable.** Cron (main's pre-buildx, amd64-only workflow) re-points `experimental-nightly` to amd64 every night. A manual full build makes it multiarch only until the next cron run. Accepted for now; becomes durable at rotation when the buildx workflow reaches main.
- `docker/build-push-action@v6` attaches a provenance attestation by default — it shows on Docker Hub as an ~81 kB `unknown/unknown` image. Set `provenance: false` to suppress it.

## Branch rotation (at v1.19 release)

```
current main/master  ──►  v1.18        (frozen maintenance, amd64-only forever)
current develop      ──►  new main      (1.19 stable)
new develop          ◄──  cut from new main
```

Constraints:
- arm64 work must **not** reach current `main` (→ v1.18).
- arm64 work must **survive** rotation — landing on `develop` propagates to both new branches.

## Steps from now until final rotation

1. **Branch** — `enh/docker-multiarch-arm64` off `develop`. PR targets `develop` only; never merge to current `main`. (done — merged via PR #12)
2. **Step 1 — nightly, develop-only** (done — merged via PR #12)
   - Convert `docker-publish-nightly.yml` to buildx (`setup-qemu-action`, `setup-buildx-action`, `build-push-action@v6`).
   - Add `--platform=$BUILDPLATFORM` to the builder stage in `image/Dockerfile`.
   - Add a `workflow_dispatch` input `platforms` (choice: `linux/amd64`, `linux/amd64,linux/arm64`, `linux/arm64`; default both) so a manual run can pick architecture explicitly — including an isolated **arm64-only** smoke test.
   - In `resolve`: use `inputs.platforms` when set (manual dispatch); otherwise fall back to the ref gate — `develop` → `linux/amd64,linux/arm64`, all other refs → `linux/amd64`. So `experimental-nightly` is multiarch and `stable-nightly`/v1.18 stays amd64-only.
3. **Validate (Option A — no change to current main)** — automated cron nightly runs `main`'s workflow copy, so validate via **manual dispatch from the develop branch**, which runs develop's copy:
   ```
   gh workflow run docker-publish-nightly.yml --ref develop
   # or select a specific platform set in the Actions UI via the `platforms` input
   ```
   Then pull `humhub/humhub:experimental-nightly` on ARM hardware; confirm build + boot. Current `main` is untouched; automated multiarch nightly switches on for free at rotation (develop → new main).
4. **Step 1a — rolling-tag guard + provenance** (follow-up fix to Step 1)
   - In `resolve`, compute the ref's `CANONICAL` platform set and a `push_rolling` flag (`true` only when the resolved platforms equal `CANONICAL`).
   - In the build step, always push the immutable `…-<ts>-<sha>` tag; push the rolling `experimental-nightly` tag only when `push_rolling == 'true'`. Narrowed manual runs (amd64-only / arm64-only) therefore publish the immutable tag only and never move `experimental-nightly`.
   - Add `provenance: false` to drop the ~81 kB attestation image from Docker Hub.
5. **Step 2 — releases**
   - Convert `docker-publish-release.yml` to buildx the same way.
   - Gate arm64 on **HumHub version `>= 1.19`** (from the computed `MINOR`), **not** branch name. v1.18.x stays amd64-only; 1.19+ always multiarch.
6. **Merge Step 2** into `develop`.
7. **Branch rotation (v1.19 release)** — current `develop` becomes new `main`; arm64 support rides forward automatically into new `main` and new `develop`. v1.18 maintenance line is unaffected (version gate keeps it amd64-only).
