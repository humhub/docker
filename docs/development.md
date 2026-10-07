# Development

This page covers working on the Docker image itself. It is not needed for running HumHub.

## Branch mapping

The branches of this repository follow the branches of [humhub/humhub](https://github.com/humhub/humhub). Make sure the checked out docker branch matches the HumHub branch you build:

| docker branch | HumHub branch |
|---|---|
| `main` | `master` |
| `develop` | `develop` |
| `v1.x` (maintenance) | `v1.x` |

## Building the image locally

Run the build script in the `image` directory:

```bash
cd image
./build.sh                              # HumHub ref follows the current docker branch
./build.sh v1.19.0                      # build a specific HumHub tag or branch
./build.sh master humhub:local-master   # custom image tag
```

Without arguments the HumHub ref is derived from the current docker branch using the mapping above. On feature branches or a detached HEAD the script falls back to `develop`. The image is tagged `humhub:local` unless a second argument is given.

### Building for another platform

Set `PLATFORM` to build for a platform other than the host, for example an arm64 image on an amd64 machine:

```bash
PLATFORM=linux/arm64 ./build.sh v1.19.0 humhub:local-arm64
```

This needs QEMU user-mode emulation registered via binfmt. Docker Desktop ships it; on Linux run once:

```bash
docker run --privileged --rm tonistiigi/binfmt --install arm64
```

Only the runtime stage is emulated, the HumHub build stage runs natively. Expect the emulated stage to take roughly ten times longer than a native build. The result is a single-platform image in the local image store; copy it to a target machine with `docker save` and `docker load`.

## Dev stack with Docker Compose

`image/compose.yml` starts the locally built `humhub:local` image together with a MariaDB. It does not build the image itself, so run `build.sh` first. The stack is meant for development only.

Stable line, HumHub `master`:

```bash
git checkout main
cd image
./build.sh
docker compose up
```

Next release line, HumHub `develop`:

```bash
git checkout develop
cd image
./build.sh
docker compose up
```

After changing the Dockerfile or to pick up new HumHub commits, run `./build.sh` again and restart the stack.

To keep images for several refs side by side, build with a custom tag and point the stack at it via `HUMHUB_IMAGE`:

```bash
./build.sh master humhub:local-master
HUMHUB_IMAGE=humhub:local-master docker compose up
```

The variable can also be placed in an `.env` file next to `compose.yml`.
