# Docker Image Tagging Policy

## Overview

This repository builds and publishes Docker images for [HumHub](https://github.com/humhub/humhub)
to Docker Hub as `humhub/humhub`. Each branch in this repository corresponds to a branch in the
upstream HumHub source repository. The build workflow derives the HumHub source branch and the
Docker image tag directly from the current repository branch.

---

## Branch-to-Tag Mapping

### Nightly Builds

| Docker repo branch | HumHub source branch | Mutable tag | Immutable tag pattern | Notes |
|---|---|---|---|---|
| `main` | `master` | `stable-nightly` | `stable-nightly-YYYYMMDDHHMMSS-<sha7>` | permanent |
| `develop` | `develop` | `experimental-nightly` | `experimental-nightly-YYYYMMDDHHMMSS-<sha7>` | permanent |
| `v1.17` | `v1.17` | `1.17-nightly` | `1.17-nightly-YYYYMMDDHHMMSS-<sha7>` | example — see below |

`main` and `develop` are the two permanent branches. Additional version branches (e.g. `v1.17`)
are created on demand for older HumHub releases that still receive support and are removed once
that version reaches end-of-life.

Every build pushes **two tags**:

- **Mutable tag** — always points to the latest build of that branch (e.g. `stable-nightly`).
  Suitable for environments that want to stay current automatically.
- **Immutable tag** — uniquely identifies a specific build by timestamp and the upstream commit
  SHA. Suitable for pinning to a known-good state and for audit trails.

### Release Builds

The set of tags pushed depends on whether the `humhub/humhub` release originates from `develop`
(beta), `master` (new stable release), or a version branch (maintenance release).

**Beta release** (e.g. `v1.19.0-beta.1`, built from docker branch `develop`):

| Tag | Type | Description |
|---|---|---|
| `1.19.0-beta.1` | Mutable | Exact beta version |
| `1.19-beta` | Mutable | Always the latest beta of the 1.19 line |
| `1.19.0-beta.1-YYYYMMDDHHMMSS-<sha7>` | Immutable | Pinnable, audit-safe build reference |

**New stable release** (e.g. `v1.18.0`, built from docker branch `main`):

| Tag | Type | Description |
|---|---|---|
| `1.18.0` | Mutable | Exact version |
| `1.18` | Mutable | Always the latest patch of this minor version |
| `stable` | Mutable | Always the newest stable release overall |
| `1.18-beta` | Mutable | Transitions from beta to stable — points to `1.18.0` |
| `1.18.0-YYYYMMDDHHMMSS-<sha7>` | Immutable | Pinnable, audit-safe build reference |

**Maintenance release** (e.g. `v1.17.5`, built from docker branch `v1.17`):

| Tag | Type | Description |
|---|---|---|
| `1.17.5` | Mutable | Exact version |
| `1.17` | Mutable | Always the latest patch of this minor version |
| `1.17-beta` | Mutable | Consistent with all versions — points to latest `1.17.x` |
| `1.17.5-YYYYMMDDHHMMSS-<sha7>` | Immutable | Pinnable, audit-safe build reference |

The `stable` tag is intentionally absent from beta and maintenance releases — it always reflects
the newest stable release from the `master` line only, consistent with how `stable-nightly` works.

>Note that `stable` is a floating tag and will move across major versions, which may include
breaking changes.

The `X.Y-beta` tag naturally transitions across the release lifecycle: it first points to the
latest beta of that minor version, then moves forward to the stable release once published.
This means users tracking `1.19-beta` automatically receive the stable `1.19.0` once it ships.

**Why `latest` is not published**

`latest` is a conventional Docker tag with no technical special meaning beyond being the default
when no tag is specified. It is omitted from this project in favour of the more descriptive
`stable` tag, which communicates intent explicitly and is consistent with the nightly naming
convention (`stable-nightly`).

---

## Nightly Build Workflow

Scheduled builds are controlled entirely from the `main` branch to work around the GitHub Actions
limitation that cron schedules only execute from the default branch.

```
.github/workflows/
  nightly-dispatcher.yml     ← main branch only; holds the cron schedule;
                                triggers docker-publish-nightly.yml on each target branch
  docker-publish-nightly.yml ← all branches; the actual build logic
  docker-cleanup.yml         ← main branch only; cleanup job
```

> **Why "main branch only"?**
> GitHub Actions cron schedules only ever execute from the repository's default branch (`main`),
> so `nightly-dispatcher.yml` and `docker-cleanup.yml` are never triggered on other branches
> even if the files are present there. They can safely remain in version branches.

### Dispatcher workflow (`nightly-dispatcher.yml`)

Runs on a schedule and triggers `docker-publish-nightly.yml` on each listed branch via
`workflow_dispatch` with a `ref` input. Adding or removing a branch from the dispatcher
matrix is the single control point for enabling or disabling nightly builds.

### Build workflow (`docker-publish-nightly.yml`)

Executed per branch. Performs the following steps:

1. Checks out the docker repo branch
2. Logs in to Docker Hub
3. Resolves the upstream HumHub commit SHA (`git ls-remote`) and generates the immutable tag
4. Builds the Docker image with `HUMHUB_GIT_BRANCH` set to the mapped upstream branch
5. Pushes both the mutable and the immutable tag to `humhub/humhub`

### Managing Nightly Builds

**Add a new version (e.g. `v1.18`)**

1. Create branch `v1.18` from `main`.
2. On `main`, add `v1.18` to the branch matrix in `nightly-dispatcher.yml`.

**Drop support for a version (e.g. `v1.17`)**

1. Remove `v1.17` from the branch matrix in `nightly-dispatcher.yml` on `main`.
2. Optionally archive or delete the `v1.17` branch.

**Temporarily pause all nightly builds**

Disable the `nightly-dispatcher.yml` workflow via the GitHub Actions UI:
**Actions** → select the workflow → **Disable workflow**.

**Trigger a manual build** — see [Manual Builds](#manual-builds).

---

## Release Build Workflow

Release builds are triggered whenever a release is published in the upstream
[humhub/humhub](https://github.com/humhub/humhub) repository. This covers beta releases from
`develop`, stable releases from `master`, and maintenance releases from version branches.

### Trigger Flow

Builds are triggered by a `repository_dispatch` event sent from `humhub/humhub` immediately
when a release is published:

| Trigger | Source | Latency |
|---|---|---|
| `repository_dispatch` | `humhub/humhub` on `release: published` | Immediate |

### Workflow Architecture

```
humhub/humhub
  .github/workflows/
    notify-docker-release.yml  ← fires on "release: published";
                                  sends repository_dispatch to humhub/docker

humhub/docker
  .github/workflows/
    release-dispatcher.yml     ← main branch only; receives repository_dispatch;
                                  triggers docker-publish-release.yml
    docker-publish-release.yml ← all branches; reusable release build logic
```

A GitHub App with **Actions: read and write** permission, installed on `humhub/docker`, is used
to generate short-lived tokens at runtime. Store the following as secrets in `humhub/humhub`:

| Secret | Value |
|---|---|
| `APP_ID` | The GitHub App's numeric App ID |
| `APP_PRIVATE_KEY` | The GitHub App's private key (`.pem` file contents) |

### Docker Repo Branch Selection

Routing is driven entirely by `target_commitish` — the branch set as the release target in
`humhub/humhub`. It is included in the `repository_dispatch` payload automatically and is a
required input for manual `workflow_dispatch` runs.

| `target_commitish` | Docker repo branch | Beta? | Tags pushed |
|---|---|---|---|
| `develop` | `develop` | yes | version, `X.Y-beta`, immutable |
| `master` | `main` | no | version, minor, stable, `X.Y-beta`→minor, immutable |
| `v1.17` | `v1.17` | no | version, minor, `X.Y-beta`→latest patch, immutable |

### Managing Release Builds

**Add a new maintenance version (e.g. `v1.17`):**
Create the `v1.17` branch in `humhub/docker`. No changes to the release workflow are needed —
routing is driven by `target_commitish` from the release event.

**Drop support for a maintenance version (e.g. `v1.17`):**
Remove or archive the `v1.17` branch. No further release builds will be triggered for `v1.17.x`.

**Trigger a manual release build** — see [Manual Builds](#manual-builds).

---

## Manual Builds

Both the nightly and release pipelines expose two entry points for manual triggering: the
**dispatcher** workflow and the **build** workflow. They serve different purposes.

### Nightly builds

| Entry point | Workflow | Branches triggered | Typical use |
|---|---|---|---|
| Dispatcher | `Nightly Build Dispatcher` | All branches in the matrix | Re-run all nightly builds at once; validate after changing the matrix |
| Build workflow | `Docker Publish Nightly Image CI` | One branch (your choice) | Debug a single branch; test a Dockerfile change in isolation |

**Via dispatcher** — triggers the full matrix in one shot:

**Actions** → `Nightly Build Dispatcher` → **Run workflow** → select `main` → **Run workflow**

**Via build workflow** — targets a single branch:

**Actions** → `Docker Publish Nightly Image CI` → **Run workflow** → select the target branch → **Run workflow**

### Release builds

| Entry point | Workflow | Branches triggered | Typical use |
|---|---|---|---|
| Dispatcher | `Release Build Dispatcher` | Derived from `target_commitish` | Standard manual trigger; backfill a missed release |
| Build workflow | `Docker Publish Release Image CI` | Derived from `target_commitish` | Debug the build step directly; bypass dispatcher |

Both variants require the same two inputs:
- `release_tag` — the HumHub git tag (e.g. `v1.18.2` or `v1.19.0-beta.1`)
- `target_commitish` — the branch the release was cut from in `humhub/humhub` (e.g. `master`, `develop`, or `v1.17`)

**Via dispatcher** (recommended — mirrors the automated path):

**Actions** → `Release Build Dispatcher` → **Run workflow** → select `main` → fill in inputs → **Run workflow**

**Via build workflow** (direct, useful for debugging):

**Actions** → `Docker Publish Release Image CI` → **Run workflow** → select `main` → fill in inputs → **Run workflow**

> Prefer the dispatcher for routine manual runs — it follows the same code path as the automated
> trigger. Use the build workflow directly only when you need to isolate or debug the build step
> itself.

---

## Cleanup Process

A separate workflow (`docker-cleanup.yml`) runs daily at 04:33 UTC and removes stale images from
Docker Hub.

### What gets deleted

An image (digest) is considered **unused** when **all** of its tags match the immutable tag
pattern:

```
<branch>-YYYYMMDDHHMMSS-<sha7>
```

An image is considered **active** as long as it carries at least one mutable tag
(e.g. `stable-nightly`, `1.17-nightly`). Active images are never deleted.

In practice this means: when a new nightly build runs, the previous mutable tag is moved to the
new digest and the old digest becomes immutable-only. The cleanup job then removes it on its next
run.

### Dry-run mode

The cleanup script supports a `--dry-run` flag that prints what would be deleted without actually
deleting anything. To test locally:

```bash
bash image/files/dockerhub-cleanup-unused.sh \
  --namespace humhub \
  --repository humhub \
  --username <user> \
  --password <token> \
  --dry-run
```

---

## Docker Hub Tag Immutability

Docker Hub supports tag immutability rules defined by regex patterns. Configure these under
**Repository Settings → Tag immutability** in the `humhub/humhub` Docker Hub repository.

### Nightly immutable tags

Pattern — matches `stable-nightly-YYYYMMDDHHMMSS-<sha7>`, `experimental-nightly-…`, `1.17-nightly-…`:

```
^.+-nightly-[0-9]{14}-[0-9a-f]{7}$
```

Examples matched:
- `stable-nightly-20260416103300-a1b2c3d`
- `experimental-nightly-20260416103300-a1b2c3d`
- `1.17-nightly-20260416103300-a1b2c3d`

### Release immutable tags

Pattern — matches stable/maintenance (`1.18.2-…`) and beta (`1.19.0-beta.1-…`) immutable tags:

```
^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?-[0-9]{14}-[0-9a-f]{7}$
```

Examples matched:
- `1.18.2-20260416103300-a1b2c3d`
- `1.17.5-20260416103300-a1b2c3d`
- `1.19.0-beta.1-20260416103300-a1b2c3d`

### Combined pattern

To cover all immutable tags (nightly and release) with a single rule:

```
^.+-[0-9]{14}-[0-9a-f]{7}$
```

---

## Appendix

- [Release Build Walkthrough](docker-release-walkthrough.md) — step-by-step trace of a release
  build from `humhub/humhub` release published to final Docker Hub state
