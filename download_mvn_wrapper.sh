#!/usr/bin/env bash

WRAPPER_DIST="https://repo1.maven.org/maven2/org/apache/maven/wrapper/\
maven-wrapper-distribution/3.3.4/maven-wrapper-distribution-3.3.4-bin.zip"
# echo "$WRAPPER_DIST"

MAVEN_DIST="https://repo.maven.apache.org/maven2/org/apache/maven/\
apache-maven/3.9.7/apache-maven-3.9.7-bin.zip"
# echo "$MAVEN_DIST"

path="$1"
if [ -z "$path" ]; then
    # echo "Path is empty"
    path="."
fi

# Download and extract wrapper distribution
res=`curl -O -# --output-dir $path --create-dirs --skip-existing \
    "$WRAPPER_DIST"`
echo $res
unzip -uo '*.zip' -d .
rm *.zip

# Generate the 'maven-wrapper.properties'
echo "Generating maven-wrapper.properties"
echo "distributionUrl=$MAVEN_DIST" > '.mvn/wrapper/maven-wrapper.properties'

echo -e "\nAll done!"
