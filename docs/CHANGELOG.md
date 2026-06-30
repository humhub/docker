Changelog
=========

June 30, 2026
-------------
- Fix: Strip X-Accel-Redirect header from responses so it is not exposed to clients (e.g. Cloudflare)

June 16, 2026
--------------
- Added experimental linux/arm64 multiarch support to nightly develop builds via buildx

Jun 09, 2026
--------------
- Better handle module migrations on core upgrades

May 28, 2026
--------------
- Remove default theme from themes folder (deprecated since HumHub v1.19)
- Added APCu PHP extension to runtime image
- Added docker hub overview page

April 17, 2026
--------------
- Introduced automated docker beta builds on humhub releases

April 16, 2026
--------------
- Introduced automated docker version builds on humhub releases

April 15, 2026
--------------
- Introduced docker image tagging policy to documentation
- Added multi branch build workflow

April 13, 2026
--------------
- Added build tags to nightly builds
- Added cleanup workflow for unused docker hub images
- Rename publish workflow to publish-nightly

April 7, 2026
--------------
- Updated ci workflow to tag nightly builds as stable/experimental-nightly on humhub/humhub

March 30, 2026
--------------
- Enh: Optional optimization for temporary storage usage
- Updated backup-restore.md to include optional HUMHUB_DOCKER__BACKUP_MERGE_ARCHIVES variable

March 16, 2026
--------------
- Introduced multi service setup
- Added simple health check and env variables for service config
- Unified HUMHUB_DOCKER_* env variable naming

March 9, 2026
-------------
- Added Restore instructions to backup-restore.md
- Faulty curly bracket removed
- Optimized image size
- Introduced CHANGELOG.md
