setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
    # get the containing directory of this file
    # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0, as those will
    # point to the bats executable's location or the preprocessed
    # file respectively
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    # make executables in src/ visible to PATH
    PATH="$DIR/../src:$PATH"
    # cd into the example directory
    cd ./test/example
}

@test "can run the script" {
    run docker-dev-from-env.sh --help
}

@test "detects Dockerfile in working directory" {
    echo "# In directory: $( pwd )" >&3
    run docker-dev-from-env.sh
    refute_output --partial 'Dockerfile does not exist in current directory'
}

@test "exits with error if Dockerfile not found in working directory" {
    cd ../
    echo "# In directory: $( pwd )" >&3
    run docker-dev-from-env.sh
    assert_output --partial 'Dockerfile does not exist in current directory'
}
