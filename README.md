<div align="center">
# docker-scripts

[Installation](#installation) •
[Usage](#usage) •

</div>

## Installation

Extract the scripts located in the `src` directory. Place them somewhere on your path, e.g. `/usr/local/bin`. All bash scripts which require root-user permissions will selectively prompt for them

## Usage

### docker-dev-from-env.sh

This script:

- Closes all running containers that are descendants of the image name passed
  in
- Builds a new image from the local Dockerfile
- Sets up a development environment via a bind mount
- Executes the passed command inside of the container
  - If not passed a command, nothing is executed
  - If passed "sh", it launches an interactive shell session
- Removes the container when done, unless the --preserve flag is passed in

The script also optionally accepts a file containing environment vars which
correspond to the command line flags. The environment vars are applied first,
then overwritten by any other args passed in.

`./docker-dev-from-env.sh --help`

Docker will not be passed a -t flag if the script is run from an environment
that does not support tty.

#### Examples

```bash
# Run with command line flags based on .env
docker-dev-from-env -e ./.env -p

# Run a command
docker-dev-from-env -c "yarn install && yarn run test"

# Start a container and run an interactive shell session. Preserve the
# container afterwards
docker-dev-from-env -c "sh" -p

# Run a container for the image "example", with the host directory ./ copied to
# the container as /app, then list from /app in the container
docker-dev-from-env -i example -s ./ -t /app -c ls
```
