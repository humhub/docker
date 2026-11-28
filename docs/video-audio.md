# Video and Audio Files (ffmpeg)

The image includes [ffmpeg](https://ffmpeg.org/) and `ffprobe` from the Debian packages, and HumHub is configured to
use them:

| Environment variable | Default | Used for |
|---|---|---|
| `HUMHUB_CONFIG__MODULES__FILE__FFPROBE_PATH` | `/usr/bin/ffprobe` | Width, height and duration of uploaded videos and audio files |
| `HUMHUB_CONFIG__MODULES__FILE__FFMPEG_PATH` | `/usr/bin/ffmpeg` | The audio track of a video or audio file for speech recognition, e.g. for a module that creates subtitles with AI |

Both need HumHub 1.20 or newer. What HumHub does with them is described in the HumHub documentation
(`docs/admin/video-audio.md` of the HumHub repository).

## Turning them off

Set a variable to an empty value:

- without `ffprobe`, HumHub reads the metadata with its built-in reader (getID3), which knows the common formats;
- without `ffmpeg`, modules that need the audio track can't process videos.

```yaml
services:
  humhub:
    environment:
      - HUMHUB_CONFIG__MODULES__FILE__FFPROBE_PATH=
      - HUMHUB_CONFIG__MODULES__FILE__FFMPEG_PATH=
```

## Long videos

The audio track of a long video is made by the queue workers (`HUMHUB_DOCKER__AUTOSTART_WORKER`), never in a web
request; a conversion is stopped after 10 minutes. Keep the workers running when you use a module that creates
subtitles.
