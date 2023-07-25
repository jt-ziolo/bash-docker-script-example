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

```
# ./docker-dev-from-env.sh --help

 Help using ./src/docker-dev-from-env.sh

  -e --env         [arg] Path to file containing environment vars
  -i --img-name    [arg] Name used for the docker image.
                         Default="default"
  -s --src-dir     [arg] Source directory for the bind mount.
                         Default="./"
  -t --target-dir  [arg] Target directory for the bind mount.
                         Default="/app"
  -c --cmd         [arg] Commands to run inside the container, runs
                         an interactive shell session if "sh" is passed
  -p --preserve          If present, the container is not removed after it
                         finishes running the command, but it may still stop
                         if not kept running by another process
  -v --verbose           Enable verbose mode, print script as it is executed
  -d --debug             Enables debug mode
  -h --help              This page
  -n --no-color          Disable color output
```

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
