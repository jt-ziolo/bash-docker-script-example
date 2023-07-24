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

	echo "# In directory: $(pwd)" >&3
}

function teardown {
	# Remove the test image and container if they exist
	docker rm -f test-container 2>/dev/null &
	docker rm -f test-container-0 2>/dev/null &
	docker rm -f test-container-1 2>/dev/null &
	docker rm -f test-container-2 2>/dev/null &
	docker rm -f test-image-dev 2>/dev/null &
	docker rm -f test-image-distinct-dev 2>/dev/null &
	docker rm -f exampleapp-dev 2>/dev/null &
	docker rmi test-image 2>/dev/null &
	docker rmi test-image-distinct 2>/dev/null &
	docker rmi exampleapp 2>/dev/null &
}

function can_run_the_script { #@test
	run docker-dev-from-env.sh --help
}

function detects_Dockerfile_in_working_directory { #@test
	run docker-dev-from-env.sh
	refute_output --partial "Dockerfile does not exist in current directory"
}

function exits_with_error_if_Dockerfile_not_found_in_working_directory { #@test
	cd ../
	echo "# Changed directory: $(pwd)" >&3
	run docker-dev-from-env.sh
	assert_output --partial "Dockerfile does not exist in current directory"
}

function detects_running_container_and_prints_correct_id { #@test
	docker build -t test-image .
	CID_ACTUAL=$(docker run --name test-container -d test-image)
	# need just the first 12 characters
	CID_ACTUAL=$(echo "$CID_ACTUAL" | head -c 12)
	echo "# CID_ACTUAL == $CID_ACTUAL" >&3

	run docker-dev-from-env.sh -i test-image
	assert_output --partial "Stopping existing test-image containers..."
}

function detects_multiple_running_containers_and_prints_correct_ids { #@test
	docker build -t test-image .

	CIDS_ACTUAL=()
	for i in {1..3}; do
		echo "# Run container $i" >&3
		CID_ACTUAL=$(docker run --name test-container-"$i" -d test-image)
		# need just the first 12 characters
		CID_ACTUAL=$(echo "$CID_ACTUAL" | head -c 12)
		#echo "# CID_ACTUAL == $CID_ACTUAL" >&3
		CIDS_ACTUAL+=("$CID_ACTUAL")
	done
	#echo "# ${CIDS_ACTUAL[*]}" >&3
	#echo "# $(docker ps -a)" >&3
	run docker-dev-from-env.sh -i test-image
	assert_output --partial "Stopping existing test-image containers..."
	for CID in "${CIDS_ACTUAL[@]}"; do
		assert_output --partial "$CID"
		echo "# Asserted for ID: $CID" >&3
	done
}

function builds_image_if_it_does_not_exist { #@test
	run docker-dev-from-env.sh -i test-image-distinct
	assert_output --partial "Building docker image: test-image-distinct"
	assert [ "$(docker images -q test-image-distinct 2>/dev/null)" != "" ]
}

function runs_container_with_correct_bind_mount_params { #@test
	run docker-dev-from-env.sh -i test-image -s ./ -t /destination
	assert_output --partial "Running container as \"test-image-dev\", mounting ./ at /destination"
}

function runs_container_and_shows_failing_test_result { #@test
	run docker-dev-from-env.sh -i test-image -s ./ -t /app -c "yarn install && yarn run test"
	assert_output --partial "1 passing"
	assert_output --partial "1 failing"
	refute_output --partial "2 failing"
	refute_output --partial "2 passing"
}

function runs_container_in_dev_mode_successfully { #@test
	run docker-dev-from-env.sh -i test-image -s ./ -t /app -c "yarn install && yarn run dev"
	assert_output --partial "$ node ./src/index.js"
	assert_output --partial "Hello world!"
	assert_output --partial "I depend on a third party library, see?"
	assert_output --partial "I've been up for 1 seconds"
	assert_output --partial "I've been up for 2 seconds"
	assert_output --partial "I've been up for 3 seconds"
	assert_output --partial "Done"
}

function preserves_container_if_configured { #@test
	run docker-dev-from-env.sh -i test-image -s ./ -t /app -c "echo hello" -p
	assert_output --partial "hello"
	# Not the best way to test this but it'll do
	refute_output --partial "Docker will remove the container once all processes finish."
	docker rm -f test-image-dev
}

function removes_container_if_preserve_not_configured { #@test
	run docker-dev-from-env.sh -i test-image -s ./ -t /app -c "echo hello"
	assert_output --partial "hello"
	# Not the best way to test this but it'll do
	assert_output --partial "Docker will remove the container once all processes finish."
}

function reads_env_file { #@test
	run docker-dev-from-env.sh -e ./.env
	assert_output --partial "1 passing"
	assert_output --partial "1 failing"
	refute_output --partial "2 failing"
	refute_output --partial "2 passing"
}

function does_not_read_env_file_unless_passed { #@test
	run docker-dev-from-env.sh -e ./.env
	run docker-dev-from-env.sh -i test-image -c "echo hello" -p
	# May cause unwarranted failure if the defaults change
	assert_output --partial "Running container as \"test-image-dev\", mounting ./ at /app"
	assert_output --partial "hello"
	docker rm -f test-image-dev
}

function overwrites_env_file_with_flags { #@test
	run docker-dev-from-env.sh -e ./.env -i test-image -s ./src -t /whoops -c "echo \"Do not run tests\""
	assert_output --partial "Running container as \"test-image-dev\", mounting ./src at /whoops"
	assert_output --partial "Docker will remove the container once all processes finish."
	assert_output --partial "Do not run tests"
	refute_output --partial "passing"
	refute_output --partial "failing"
}

function partially_overwrites_env_file_with_flags { #@test
	run docker-dev-from-env.sh -e ./.env -i test-image -t /whoops -c "echo \"Do not run tests\""
	assert_output --partial "Running container as \"test-image-dev\", mounting ./ at /whoops"
	assert_output --partial "Docker will remove the container once all processes finish."
	assert_output --partial "Do not run tests"
	refute_output --partial "passing"
	refute_output --partial "failing"
}
