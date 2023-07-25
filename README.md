<div align="center">
  
# docker-scripts

A small collection of Bash and Python scripts I use to interact with Docker while building projects.

</div>

## Installation

Extract the scripts located in the `src` directory. Place them somewhere on your path, e.g. `/usr/local/bin`. 

## Usage

### docker-dev-from-env.sh

Note: All bash scripts which require root-level permissions for any commands will prompt you for them (there is no need to run these scripts with sudo).

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
# Run the script with command line flags based on .env
docker-dev-from-env -e ./.env -p

# Builds an image and runs a container with a bind mount from ./ to /app, where
# the container will start and run "yarn install && yarn run test" before being removed.
docker-dev-from-env -c "yarn install && yarn run test"

# Builds an image and runs a container with a bind mount from ./ to /app, where
# the container will start and run an interactive shell session. The container
# will be preserved afterwards.
docker-dev-from-env -c "sh" -p

# Builds an image named "example" and runs a container with a bind mount from ./src to
# /export, where the container will start and list the contents at the root directory.
docker-dev-from-env -i example -s ./src -t /export -c ls
```
