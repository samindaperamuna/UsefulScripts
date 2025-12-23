#!/usr/bin/env bash

SCRIPT_VERSION='0.10a'
GRADLE_VERSION='9.2.1'
MAVEN_VERSION='3.9.7'

# Wrapper and distribution URLs
MAVEN_WRAPPER_URL="https://repo1.maven.org/maven2/org/apache/maven/wrapper/\
maven-wrapper-distribution/3.3.4/maven-wrapper-distribution-3.3.4-bin.zip"
GRADLE_WRAPPER_URL="https://raw.githubusercontent.com/gradle/gradle/master/\
gradle/wrapper/gradle-wrapper.jar"
MAVEN_DIST_URL='https://repo.maven.apache.org/maven2/org/apache/maven/'\
'apache-maven/$MAVEN_VERSION/apache-maven-$MAVEN_VERSION-bin.zip'
GRADLE_DIST_URL='https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip'

# Usage message
MSG=$(cat <<EOF
Usage: $0 [-option] -t <wrapper_type>
    Download and setup either Gradle or Maven wrapper.

    Options: 
    -t --type       Wrapper type ( one of ['g','m','gradle','maven']). Required!

    -v --version    Version of the Gradle or Maven distribution used by the wrapper
                    If no version is provided following default versions will be used.

                    Default Gradle version: $GRADLE_VERSION   
                    Default Maven version: $MAVEN_VERSION 

    -p --path       Installation path
                    If no path is provided current directory will be used.

    -V              Script version 

    -h --help       Prints this help message.

    Debug options:
    -d --debug      Prints debug data.
EOF
)

# Helper functions to ease testing
# Can be overloaded in the bats test
get_gradle_wrapper_url() {
    echo $GRADLE_WRAPPER_URL
}

get_maven_wrapper_url() {
    echo $MAVEN_WRAPPER_URL
}

# Lowercase wrapper type so the value can be of either case.
declare -l wrapper_type
declare isDebug=false

print() {
    msg=$1
    [[ -z "$2" || "$2" -ne 0 ]] && msg="$msg\n"
    echo -e "$msg"
}

die() {
    echo -e "${2:-$MSG}"
    exit "${1:-0}"
}

print_version() {
    arg_count=$1 
    if [[ $arg_count -eq 1 ]]; then 
        die 0 "Version: $SCRIPT_VERSION"
    fi
}

debug() {
    [ $# -lt 1 ] && return 0 

    if $isDebug; then
        echo -e "$1"
    fi
}

if_dist_exist() {
    curl -s "$1"
    curl_exit_status=$?

    return $curl_exit_status
}

handle_response() {
    curl_exit_stat=$1

    debug "Curl exit code is $curl_exit_stat"
    [ $curl_exit_stat -ne 0 ] && die $curl_exit_stat "Failed to download wrapper! exiting ..." 
}

## Validate flags
while getopts ":t:v:p:Vhd" flag
do
    case "$flag" in
        t) wrapper_type=${OPTARG};;
        v) dist_version=${OPTARG};;
        p) install_path=${OPTARG};; 
        V) print_version $#;;
        h) die;;
        d) isDebug=true;;
        \?) die 1 "Invalid option: -${OPTARG}\n\n$MSG";; 
        :) die 1 "Option -${OPTARG} requires a value\n\n$MSG";; 
    esac
done

debug "Shifting parms by: $((OPTIND - 1))"

# Shift positional parameters by 
shift $(($OPTIND - 1))

debug "Current argument index $OPTIND"
debug "Current positional argument $1"

[ $# -gt 0 ] && die 1 "Invalid argument(s): $*"

# Assign default values
if [[ "$wrapper_type" = "g" || "$wrapper_type" = "gradle" ]]; then 
    wrapper_type="gradle"
    wrapper_url=$(get_gradle_wrapper_url)
    : "${dist_version:=$GRADLE_VERSION}"
    dist_url=${GRADLE_DIST_URL//'$GRADLE_VERSION'/"$dist_version"}
elif [[ "$wrapper_type" = "m" || "$wrapper_type" = "maven" ]]; then 
    wrapper_type="maven"
    wrapper_url=$(get_maven_wrapper_url)
    : "${dist_version:=$MAVEN_VERSION}"
    dist_url="${MAVEN_DIST_URL//'$MAVEN_VERSION'/"$dist_version"}"
else
    if [ -z "$wrapper_type" ]; then
        die 1 "Missing wrapper type\n\n$MSG"
    else
        die 1 "Invalid wrapper type: $wrapper_type\n\n$MSG"
    fi
fi

: "${install_path:=.}"

# Debug print values
debug "Wrapper type: $wrapper_type"
debug "Dist version: $dist_version"
debug "Install path: $install_path"
debug "Wrapper URL: $wrapper_url"
debug "Dist URL: $dist_url"

# Check if wrapper exists
if_dist_exist $wrapper_url -ne 0 && die "Wrapper URL: $wrapper_url is unreachable." 

# Download and extract wrapper distribution
print "Downloading wrapper ditribution ..."
if [ "$wrapper_type" = "gradle" ]; then
    wrapper_path="${install_path}/gradle/wrapper"

    debug "Gradle wrapper path: $wrapper_path"

    curl -f -O -# --output-dir "$wrapper_path" --create-dirs --skip-existing \
        "$wrapper_url"
    handle_response $?

    # Generate the 'gradle-wrapper.properties'
    print "Generating gradle-wrapper.properties ..."

    cat > "${wrapper_path}"/gradle-wrapper.properties <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=$dist_url
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

    print "Setting up gradle wrapper scripts ..."
    # Need to be inside the installation directory
    # Its where we generate the wrapper scripts
    cd "$install_path" || exit 2

    debug "Current dir: $(pwd)" 

    # Setup gradle executable scripts
    debug "Java classpath: ${wrapper_path}/gradle-wrapper.jar"

    # Todo: Ignore this for the time being as this is outside of the script's scope.
    # User can run the wrapper manually.
    #
    # Initialize gradle project
    # print Initializing gradle project
    # java -cp "gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain wrapper
elif [ "$wrapper_type" = "maven" ]; then
    curl -O -# -f --output-dir "$install_path" --create-dirs --skip-existing \
        "$wrapper_url"
    handle_response $?

    print "Extracting archive ..."
    cd "$install_path" || exit 2
    unzip -uo '*.zip' -d .
    rm ./*.zip*

    # Generate the 'maven-wrapper.properties'
    print "Generating maven-wrapper.properties ..."
    echo "distributionUrl=$dist_url" > '.mvn/wrapper/maven-wrapper.properties'
fi    
 
print "\nAll done!"
