# Command Line Interface

Some administrative tasks can also or exclusively be executed by console. All available console commands can be displayed
by running the `yii` command with no arguments.

You run the command on the **host**, in the directory that holds your `compose.yml`. Docker executes it inside the running `humhub` container:

```bash
docker compose exec humhub /app/yii <command>
```

## Examples

List all available commands by leaving the route out:

```bash
docker compose exec humhub /app/yii
```

Flush the caches:

```bash
docker compose exec humhub /app/yii cache/flush-all
```

Include module migrations:

```bash
docker compose exec humhub /app/yii migrate/up --includeModuleMigrations=1
```

As a further variant you can address the container by its id instead, which is handy in scripts and outside the Compose directory:

```bash
docker exec -it $(docker compose ps -q humhub) /app/yii cache/flush-all
```

## Command reference

The most important commands used to administer HumHub are listed in the
[HumHub Command Line Interface guide](https://docs.humhub.org/docs/admin/console).
