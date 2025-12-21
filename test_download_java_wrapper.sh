#!/usr/bin/env bats 

script_under_test="./download_java_wrapper.sh"

# Script wide variables
MAVEN_WRAPPER_URL="https://repo1.maven.org/maven2/org/apache/maven/wrapper/\
    maven-wrapper-distribution/3.3.4/maven-wrapper-distribution-3.3.4-bin.zip"
GRADLE_WRAPPER_URL="https://raw.githubusercontent.com/gradle/gradle/master/\
    gradle/wrapper/gradle-wrapper.jar"

setup () {
    incorrect_maven_wrapper_url=${MAVEN_WRAPPER_URL/maven/"maven/test"}
    incorrect_gradle_wrapper_url=${GRADLE_WRAPPER_URL/gradle/"gradle/test"}

    # Mock methods
    get_maven_wrapper_url () {
        return $incorrect_maven_wrapper_url
    }

    get_gradle_wrapper_url () {
        return $incorrect_gradle_wrapper_url
    }
}

# Basic download test on maven wrapper
@test "Download maven wrapper with incorrect URL" {
    # Export the overridden method
    export -f get_maven_wrapper_url

    # Source the script
    # source $script_under_test 

    run $script_under_test -dt m -p "maven_test"

    # Cleanup
    rm -rf maven_test >/dev/null 2>1&
}

# Basic download test on gradle wrapper
@test "Download gradle wrapper with incorrect URL" {
    # Export the overridden method
    export -f get_gradle_wrapper_url

    # Source the script
    load $script_under_test 

    run $script_under_test -dt g -p "gradle_test"
}

# # Test test
# @test "Test the die function" {
#     load $script_under_test 
#     run die 
# }

# TODO: Add more tests
