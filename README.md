# UsefullScripts

Bash scripts which might be useful to someone

## Download JAVA Wrapper

Script to setup Gradle/Maven wrapper for your JAVA project without having to have a local Gradle/Maven installation.

`usage: ./download_java_wrapper.sh -t <wrapper_type> [-options]`

## Auto Copy Resource

This script monitors static files (specifically for JAVA project resources) and copy them if changed into target directory. The list of files to monitor relative to the script directory should be provided in the "resources" file.

`usage: ./auto_copy_resources.sh [-options]`

## Update Discord for non Debian based distros

Discord currently only support Debian based package managers directly. The other Linux distros have to rely on the tarball archive and manual setup  (Discord wont mention if there are any updates). This script helps to close any running Discord instances and download the latest update and extract into the installtion directory.

`usage: ./update_discord.sh`
