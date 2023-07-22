#!/usr/bin/env bash

function setup {
	load "test_helper/bats-support/load"
	load "test_helper/bats-assert/load"
	# get the containing directory of this file
	# use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0, as those will
	# point to the bats executable's location or the preprocessed
	# file respectively
	DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
	# make executables in src/ visible to PATH
	PATH="$DIR/../src:$PATH"
	# cd into the example directory
	cd ./test/example || exit
}

function teardown {
	# Remove the test image and container if they exist
	docker rm -f test-container 2>/dev/null & # don't keep open this script's stderr
	docker rmi test-image 2>/dev/null &       # don't keep open this script's stderr
}

function can_run_the_script { #@test
	run docker-dev-from-env.sh --help
}

function detects_Dockerfile_in_working_directory { #@test
	echo "# In directory: $(pwd)" >&3
	run docker-dev-from-env.sh
	refute_output --partial "Dockerfile does not exist in current directory"
}

function exits_with_error_if_Dockerfile_not_found_in_working_directory { #@test
	cd ../
	echo "# In directory: $(pwd)" >&3
	run docker-dev-from-env.sh
	assert_output --partial "Dockerfile does not exist in current directory"
}

function detects_running_container_and_prints_correct_id { #@test
	echo "# In directory: $(pwd)" >&3

	echo "# Run container" >&3
	docker build -t test-image .
	CID_ACTUAL=$(docker run --name test-container -d test-image)
	# need just the first 12 characters
	CID_ACTUAL=$(echo $CID_ACTUAL | head -c 12)
	echo "# CID_ACTUAL == $CID_ACTUAL" >&3

	run docker-dev-from-env.sh -i test-image
	assert_output --partial "Removing existing container with ID: $CID_ACTUAL"
}

function detects_multiple_running_containers_and_prints_correct_ids { #@test
	echo "# In directory: $(pwd)" >&3

	# for ((i = 0 ; i < 100 ; i++)); do
	# echo "$i"
	# done
	echo "# Run container" >&3
	docker build -t test-image .
	CID_ACTUAL=$(docker run --name test-container -d test-image)
	# need just the first 12 characters
	CID_ACTUAL=$(echo $CID_ACTUAL | head -c 12)
	echo "# CID_ACTUAL == $CID_ACTUAL" >&3

	run docker-dev-from-env.sh -i test-image
	assert_output --partial "Removing existing container with ID: $CID_ACTUAL"
}
