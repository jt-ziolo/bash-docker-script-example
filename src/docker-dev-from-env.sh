#!/usr/bin/env bash
#
# docker-dev-from-env.sh
##############################################################################
# This script:
#   - Closes all running containers that are descendants of the image name
#   passed in
#   - Builds a new image from the local Dockerfile
#   - Sets up a development environment via a bind mount
#   - Executes the passed command inside of the container
#   	- If not passed a command, nothing is executed
#   	- If passed "sh", it launches an interactive shell session
#   - Removes the container when done unless the --preserve flag is passed in
#
# The script also optionally accepts a file containing environment vars which
# correspond to the command line flags. The environment vars are applied first,
# then overwritten by any other args passed in.
#
# Usage:
#
#  ./docker-dev-from-env.sh --help
#
##############################################################################
# Based on a template by BASH3 Boilerplate v2.4.1
# http://bash3boilerplate.sh/#authors
#
# The MIT License (MIT)
# Copyright (c) 2013 Kevin van Zonneveld and contributors
# You are not obligated to bundle the LICENSE file with your b3bp projects as
# long as you leave these references intact in the header comments of your
# source files.
##############################################################################
# Note: This source file shares the same license (MIT) as the template file
##############################################################################

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
	__i_am_main_script="0" # false

	if [[ "${__usage+x}" ]]; then
		if [[ "${BASH_SOURCE[1]}" = "${0}" ]]; then
			__i_am_main_script="1" # true
		fi

		__b3bp_external_usage="true"
		__b3bp_tmp_source_idx=1
	fi
else
	__i_am_main_script="1" # true
	[[ "${__usage+x}" ]] && unset -v __usage
	[[ "${__helptext+x}" ]] && unset -v __helptext
fi

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")"
__base="$(basename "${__file}" .sh)"
# shellcheck disable=SC2034,SC2015
__invocation="$(printf %q "${__file}")$( (($#)) && printf ' %q' "$@" || true)"

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected

### Functions
##############################################################################

function __b3bp_log() {
	local log_level="${1}"
	shift

	# shellcheck disable=SC2034
	local color_debug="\\x1b[35m"
	# shellcheck disable=SC2034
	local color_info="\\x1b[32m"
	# shellcheck disable=SC2034
	local color_notice="\\x1b[34m"
	# shellcheck disable=SC2034
	local color_warning="\\x1b[33m"
	# shellcheck disable=SC2034
	local color_error="\\x1b[31m"
	# shellcheck disable=SC2034
	local color_critical="\\x1b[1;31m"
	# shellcheck disable=SC2034
	local color_alert="\\x1b[1;37;41m"
	# shellcheck disable=SC2034
	local color_emergency="\\x1b[1;4;5;37;41m"

	local colorvar="color_${log_level}"

	local color="${!colorvar:-${color_error}}"
	local color_reset="\\x1b[0m"

	if [[ "${NO_COLOR:-}" = "true" ]] || { [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]]; } || [[ ! -t 2 ]]; then
		if [[ "${NO_COLOR:-}" != "false" ]]; then
			# Don't use colors on pipes or non-recognized terminals
			color=""
			color_reset=""
		fi
	fi

	# all remaining arguments are to be printed
	local log_line=""

	while IFS=$'\n' read -r log_line; do
		echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${color_reset} ${log_line}" 1>&2
	done <<<"${@:-}"
}

function emergency() {
	__b3bp_log emergency "${@}"
	exit 1
}
function alert() {
	[[ "${LOG_LEVEL:-0}" -ge 1 ]] && __b3bp_log alert "${@}"
	true
}
function critical() {
	[[ "${LOG_LEVEL:-0}" -ge 2 ]] && __b3bp_log critical "${@}"
	true
}
function error() {
	[[ "${LOG_LEVEL:-0}" -ge 3 ]] && __b3bp_log error "${@}"
	true
}
function warning() {
	[[ "${LOG_LEVEL:-0}" -ge 4 ]] && __b3bp_log warning "${@}"
	true
}
function notice() {
	[[ "${LOG_LEVEL:-0}" -ge 5 ]] && __b3bp_log notice "${@}"
	true
}
function info() {
	[[ "${LOG_LEVEL:-0}" -ge 6 ]] && __b3bp_log info "${@}"
	true
}
function debug() {
	[[ "${LOG_LEVEL:-0}" -ge 7 ]] && __b3bp_log debug "${@}"
	true
}

function help() {
	echo "" 1>&2
	echo " ${*}" 1>&2
	echo "" 1>&2
	echo "  ${__usage:-No usage available}" 1>&2
	echo "" 1>&2

	if [[ "${__helptext:-}" ]]; then
		echo " ${__helptext}" 1>&2
		echo "" 1>&2
	fi

	exit 1
}

### Parse commandline options
##############################################################################

# Commandline options. This defines the usage page, and is used to parse cli
# opts & defaults from. The parsing is unforgiving so be precise in your syntax
# - A short option must be preset for every long option; but every short option
#   need not have a long option
# - `--` is respected as the separator between options and arguments
# - We do not bash-expand defaults, so setting '~/app' as a default will not resolve to ${HOME}.
#   you can use bash variables to work around this (so use ${HOME} instead)

# shellcheck disable=SC2015
[[ "${__usage+x}" ]] || read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
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
EOF

# shellcheck disable=SC2015
[[ "${__helptext+x}" ]] || read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
	 This script closes all running containers that are descendants of the
	 image name passed in, then builds a new image from the Dockerfile,
	 setting up a development environment via a bind mount while doing so.
	 It then executes the passed command inside of the container, removing
	 the container when done unless the --preserve flag is passed in.

	 When using the --env flag, the file containing environment vars should
	 use screaming snake case names based on the multi-character command
	 line flags prefixed with DS_DFE_, e.g. DS_DFE_IMG_NAME="api-img" is
	 equivalent to passing "--img-name api-img". Environment vars
	 introduced by --env are overwritten by other flags, if they are
	 provided.

	 Examples:
	   - Run with command line flags based on .env
	             docker-dev-from-env -e ./.env

	   - Run a command
	             docker-dev-from-env -c "yarn install && yarn run test" -k

	   - Start a container and run an interactive shell session, preserving
	   it afterwards
	             docker-dev-from-env -c "sh" -p

	   - Run a container for the image "example", with the host directory
	   ./ copied to the container as /app, then list from /app in the
	   container
	             docker-dev-from-env -i example -s ./ -t /app -c ls
EOF

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read -r __b3bp_tmp_line; do
	if [[ "${__b3bp_tmp_line}" =~ ^- ]]; then
		# fetch single character version of option string
		__b3bp_tmp_opt="${__b3bp_tmp_line%% *}"
		__b3bp_tmp_opt="${__b3bp_tmp_opt:1}"

		# fetch long version if present
		__b3bp_tmp_long_opt=""

		if [[ "${__b3bp_tmp_line}" = *"--"* ]]; then
			__b3bp_tmp_long_opt="${__b3bp_tmp_line#*--}"
			__b3bp_tmp_long_opt="${__b3bp_tmp_long_opt%% *}"
		fi

		# map opt long name to+from opt short name
		printf -v "__b3bp_tmp_opt_long2short_${__b3bp_tmp_long_opt//-/_}" '%s' "${__b3bp_tmp_opt}"
		printf -v "__b3bp_tmp_opt_short2long_${__b3bp_tmp_opt}" '%s' "${__b3bp_tmp_long_opt//-/_}"

		# check if option takes an argument
		if [[ "${__b3bp_tmp_line}" =~ \[.*\] ]]; then
			__b3bp_tmp_opt="${__b3bp_tmp_opt}:" # add : if opt has arg
			__b3bp_tmp_init=""                  # it has an arg. init with ""
			printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "1"
		elif [[ "${__b3bp_tmp_line}" =~ \{.*\} ]]; then
			__b3bp_tmp_opt="${__b3bp_tmp_opt}:" # add : if opt has arg
			__b3bp_tmp_init=""                  # it has an arg. init with ""
			# remember that this option requires an argument
			printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "2"
		else
			__b3bp_tmp_init="0" # it's a flag. init with 0
			printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "0"
		fi
		__b3bp_tmp_opts="${__b3bp_tmp_opts:-}${__b3bp_tmp_opt}"

		if [[ "${__b3bp_tmp_line}" =~ ^Can\ be\ repeated\. ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Can\ be\ repeated\. ]]; then
			# remember that this option can be repeated
			printf -v "__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}" '%s' "1"
		else
			printf -v "__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}" '%s' "0"
		fi
	fi

	[[ "${__b3bp_tmp_opt:-}" ]] || continue

	if [[ "${__b3bp_tmp_line}" =~ ^Default= ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Default= ]]; then
		# ignore default value if option does not have an argument
		__b3bp_tmp_varname="__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}"
		if [[ "${!__b3bp_tmp_varname}" != "0" ]]; then
			# take default
			__b3bp_tmp_init="${__b3bp_tmp_line##*Default=}"
			# strip double quotes from default argument
			__b3bp_tmp_re='^"(.*)"$'
			if [[ "${__b3bp_tmp_init}" =~ ${__b3bp_tmp_re} ]]; then
				__b3bp_tmp_init="${BASH_REMATCH[1]}"
			else
				# strip single quotes from default argument
				__b3bp_tmp_re="^'(.*)'$"
				if [[ "${__b3bp_tmp_init}" =~ ${__b3bp_tmp_re} ]]; then
					__b3bp_tmp_init="${BASH_REMATCH[1]}"
				fi
			fi
		fi
	fi

	if [[ "${__b3bp_tmp_line}" =~ ^Required\. ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Required\. ]]; then
		# remember that this option requires an argument
		printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "2"
	fi

	# Init var with value unless it is an array / a repeatable
	__b3bp_tmp_varname="__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}"
	[[ "${!__b3bp_tmp_varname}" = "0" ]] && printf -v "arg_${__b3bp_tmp_opt:0:1}" '%s' "${__b3bp_tmp_init}"
done <<<"${__usage:-}"

# run getopts only if options were specified in __usage
if [[ "${__b3bp_tmp_opts:-}" ]]; then
	# Allow long options like --this
	__b3bp_tmp_opts="${__b3bp_tmp_opts}-:"

	# Reset in case getopts has been used previously in the shell.
	OPTIND=1

	# start parsing command line
	set +o nounset # unexpected arguments will cause unbound variables
	# to be dereferenced
	# Overwrite $arg_<flag> defaults with the actual CLI options
	while getopts "${__b3bp_tmp_opts}" __b3bp_tmp_opt; do
		[[ "${__b3bp_tmp_opt}" = "?" ]] && help "Invalid use of script: ${*} "

		if [[ "${__b3bp_tmp_opt}" = "-" ]]; then
			# OPTARG is long-option-name or long-option=value
			if [[ "${OPTARG}" =~ .*=.* ]]; then
				# --key=value format
				__b3bp_tmp_long_opt=${OPTARG/=*/}
				# Set opt to the short option corresponding to the long option
				__b3bp_tmp_varname="__b3bp_tmp_opt_long2short_${__b3bp_tmp_long_opt//-/_}"
				printf -v "__b3bp_tmp_opt" '%s' "${!__b3bp_tmp_varname}"
				OPTARG=${OPTARG#*=}
			else
				# --key value format
				# Map long name to short version of option
				__b3bp_tmp_varname="__b3bp_tmp_opt_long2short_${OPTARG//-/_}"
				printf -v "__b3bp_tmp_opt" '%s' "${!__b3bp_tmp_varname}"
				# Only assign OPTARG if option takes an argument
				__b3bp_tmp_varname="__b3bp_tmp_has_arg_${__b3bp_tmp_opt}"
				__b3bp_tmp_varvalue="${!__b3bp_tmp_varname}"
				[[ "${__b3bp_tmp_varvalue}" != "0" ]] && __b3bp_tmp_varvalue="1"
				printf -v "OPTARG" '%s' "${@:OPTIND:${__b3bp_tmp_varvalue}}"
				# shift over the argument if argument is expected
				((OPTIND += __b3bp_tmp_varvalue))
			fi
			# we have set opt/OPTARG to the short value and the argument as OPTARG if it exists
		fi

		__b3bp_tmp_value="${OPTARG}"

		__b3bp_tmp_varname="__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}"
		if [[ "${!__b3bp_tmp_varname}" != "0" ]]; then
			# repeatables
			# shellcheck disable=SC2016
			if [[ -z "${OPTARG}" ]]; then
				# repeatable flags, they increcemnt
				__b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}"
				debug "cli arg ${__b3bp_tmp_varname} = (${__b3bp_tmp_default}) -> ${!__b3bp_tmp_varname}"
				# shellcheck disable=SC2004
				__b3bp_tmp_value=$((${!__b3bp_tmp_varname} + 1))
				printf -v "${__b3bp_tmp_varname}" '%s' "${__b3bp_tmp_value}"
			else
				# repeatable args, they get appended to an array
				__b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}[@]"
				debug "cli arg ${__b3bp_tmp_varname} append ${__b3bp_tmp_value}"
				declare -a "${__b3bp_tmp_varname}"='("${!__b3bp_tmp_varname}" "${__b3bp_tmp_value}")'
			fi
		else
			# non-repeatables
			__b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}"
			__b3bp_tmp_default="${!__b3bp_tmp_varname}"

			if [[ -z "${OPTARG}" ]]; then
				__b3bp_tmp_value=$((__b3bp_tmp_default + 1))
			fi

			printf -v "${__b3bp_tmp_varname}" '%s' "${__b3bp_tmp_value}"

			debug "cli arg ${__b3bp_tmp_varname} = (${__b3bp_tmp_default}) -> ${!__b3bp_tmp_varname}"
		fi
	done
	set -o nounset # no more unbound variable references expected

	shift $((OPTIND - 1))

	if [[ "${1:-}" = "--" ]]; then
		shift
	fi
fi

### Automatic validation of required option arguments
##############################################################################

for __b3bp_tmp_varname in ${!__b3bp_tmp_has_arg_*}; do
	# validate only options which required an argument
	[[ "${!__b3bp_tmp_varname}" = "2" ]] || continue

	__b3bp_tmp_opt_short="${__b3bp_tmp_varname##*_}"
	__b3bp_tmp_varname="arg_${__b3bp_tmp_opt_short}"
	[[ "${!__b3bp_tmp_varname}" ]] && continue

	__b3bp_tmp_varname="__b3bp_tmp_opt_short2long_${__b3bp_tmp_opt_short}"
	printf -v "__b3bp_tmp_opt_long" '%s' "${!__b3bp_tmp_varname}"
	[[ "${__b3bp_tmp_opt_long:-}" ]] && __b3bp_tmp_opt_long=" (--${__b3bp_tmp_opt_long//_/-})"

	help "Option -${__b3bp_tmp_opt_short}${__b3bp_tmp_opt_long:-} requires an argument"
done

### Cleanup Environment variables
##############################################################################

for __tmp_varname in ${!__b3bp_tmp_*}; do
	unset -v "${__tmp_varname}"
done

unset -v __tmp_varname

### Externally supplied __usage. Nothing else to do here
##############################################################################

if [[ "${__b3bp_external_usage:-}" = "true" ]]; then
	unset -v __b3bp_external_usage
	return
fi

### Signal trapping and backtracing
##############################################################################

function __b3bp_cleanup_before_exit() {
	info "Cleaning up. Done"
}
trap __b3bp_cleanup_before_exit EXIT

# requires `set -o errtrace`
__b3bp_err_report() {
	local error_code=${?}
	error "Error in ${__file} in function ${1} on line ${2}"
	exit ${error_code}
}
# Uncomment the following line for always providing an error backtrace
# trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR

### Command-line argument switches (like -d for debugmode, -h for showing helppage)
##############################################################################

# debug mode
if [[ "${arg_d:?}" = "1" ]]; then
	set -o xtrace
	PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
	LOG_LEVEL="7"
	# Enable error backtracing
	trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR
fi

# verbose mode
if [[ "${arg_v:?}" = "1" ]]; then
	set -o verbose
fi

# no color mode
if [[ "${arg_n:?}" = "1" ]]; then
	NO_COLOR="true"
fi

# help mode
if [[ "${arg_h:?}" = "1" ]]; then
	# Help exists with code 1
	help "Help using ${0}"
fi

### Validation. Error out if the things required for your script are not present
##############################################################################

# [[ "${arg_f:-}" ]] || help "Setting a filename with -f or --file is required"
[[ "${LOG_LEVEL:-}" ]] || emergency "Cannot continue without LOG_LEVEL. "

### Runtime
##############################################################################

debug "__i_am_main_script: ${__i_am_main_script}"
debug "__file: ${__file}"
debug "__dir: ${__dir}"
debug "__base: ${__base}"
debug "OSTYPE: ${OSTYPE}"

debug "Before --env assignment:"
debug "arg_e: ${arg_e}"
debug "arg_i: ${arg_i}"
debug "arg_s: ${arg_s}"
debug "arg_t: ${arg_t}"
debug "arg_p: ${arg_p}"
debug "arg_c: ${arg_c}"
debug "arg_d: ${arg_d}"
debug "arg_v: ${arg_v}"
debug "arg_h: ${arg_h}"
debug "arg_n: ${arg_n}"

# assign --env if set
if [[ "$arg_e" ]]; then
	info "Reading session env vars from $arg_e..."
	set -a
	. "$arg_e"
	set +a
	TEMP_ENV_VARS=$(env | grep -Fe DS_DFE)
	info "$TEMP_ENV_VARS"
	if [[ ! "$arg_i" ]]; then
		arg_i="$DS_DFE_IMG_NAME"
	fi
	if [[ ! "$arg_s" ]]; then
		arg_s="$DS_DFE_SRC_DIR"
	fi
	if [[ ! "$arg_t" ]]; then
		arg_t="$DS_DFE_TARGET_DIR"
	fi
	if [[ ! "$arg_p" ]]; then
		arg_p="$DS_DFE_PRESERVE"
	fi
	if [[ ! "$arg_c" ]]; then
		arg_c="$DS_DFE_CMD"
	fi
fi

debug "After --env assignment:"
debug "arg_i: ${arg_i}"
debug "arg_s: ${arg_s}"
debug "arg_t: ${arg_t}"
debug "arg_p: ${arg_p}"
debug "arg_c: ${arg_c}"

if [ ! -f "Dockerfile" ]; then
	error "Dockerfile does not exist in current directory: $(pwd)"
	exit 1
fi

# Forces removal of the running docker container that matches the image of the dockerfile.
CIDS=$(docker ps -a -q --filter ancestor="$arg_i")

if [ "$CIDS" ]; then
	info "Stopping existing $arg_i containers..."
	docker rm -f $CIDS
fi

# Builds the docker image from the dockerfile if it doesn't exist
if [[ "$(docker images -q "$arg_i" 2>/dev/null)" == "" ]]; then
	info "Building docker image: $arg_i..."
	docker build -t "$arg_i" .
fi

info "Running container as \"$arg_i-dev\", mounting $arg_s at $arg_t..."

# Set up --rm flag if the arg_p is unset
if [ "$arg_p" = "0" ]; then
	REMOVE_FLAG="1"
	info "Docker will remove the container once all processes finish."
fi

[ -t 0 ] && TTY_FLAG="1" || notice "No TTY available"

# Run the docker container and assign the bind mount
if [ ! "$arg_c" ]; then
	# nothing passed, run and exit after finished
	docker run -v "$arg_s":"$arg_t" -w "$arg_t" --name "$arg_i-dev" ${REMOVE_FLAG:+"--rm"} "$arg_i"
elif [ "$arg_c" = "sh" ]; then
	# "sh" passed, run interactive shell
	docker run -v "$arg_s":"$arg_t" -w "$arg_t" --name "$arg_i-dev" ${REMOVE_FLAG:+"--rm"} -i${TTY_FLAG:+"t"} "$arg_i" /bin/ash
else
	# run the command that was passed in
	docker run -v "$arg_s":"$arg_t" -w "$arg_t" --name "$arg_i-dev" ${REMOVE_FLAG:+"--rm"} -i${TTY_FLAG:+"t"} "$arg_i" /bin/ash -c "$arg_c"
fi
