#!/bin/sh

# This script prints a URL that can be used to populate the parameters for the build-jres job.


###
PUBLISH_LOCATION_PREFIX="sandbox-test/jres"
#
PUBLISH_LOCATION_PREFIX_ENCODED="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$PUBLISH_LOCATION_PREFIX")"

###
JUSTJ_MANIFEST_URL=""
#
JUSTJ_MANIFEST_URL_ENCODED="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$JUSTJ_MANIFEST_URL")"

###
JDK_URLS_WINDOWS="\
https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_windows-x64_bin.zip
https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7.1/OpenJDK14U-jdk_x64_windows_hotspot_14.0.1_7.zip
https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7.1_openj9-0.20.0/OpenJDK14U-jdk_x64_windows_openj9_14.0.1_7_openj9-0.20.0.zip
"
#
JDK_URLS_WINDOWS_ENCODED="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$JDK_URLS_WINDOWS")"

###
JDK_URLS_MACOS="\
https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_osx-x64_bin.tar.gz
https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7/OpenJDK14U-jdk_x64_mac_hotspot_14.0.1_7.tar.gz
https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7.2_openj9-0.20.0/OpenJDK14U-jdk_x64_mac_openj9_14.0.1_7_openj9-0.20.0.tar.gz
"
#
JDK_URLS_MACOS_ENCODED="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$JDK_URLS_MACOS")"

###
JDK_URLS_LINUX="\
https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_linux-x64_bin.tar.gz
https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7/OpenJDK14U-jdk_x64_linux_hotspot_14.0.1_7.tar.gz
https://github.com/AdoptOpenJDK/openjdk14-binaries/releases/download/jdk-14.0.1%2B7_openj9-0.20.0/OpenJDK14U-jdk_x64_linux_openj9_14.0.1_7_openj9-0.20.0.tar.gz
"
#
JDK_URLS_LINUX_ENCODED="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$JDK_URLS_LINUX")"

###
BUILD_TYPE="nightly"

###
PROMOTE="true"

echo "https://ci.eclipse.org/justj/job/build-jres/parambuild?PUBLISH_LOCATION_PREFIX=$PUBLISH_LOCATION_PREFIX&JUSTJ_MANIFEST_URL=$JUSTJ_MANIFEST_URL_ENCODED&JDK_URLS_WINDOWS=$JDK_URLS_WINDOWS_ENCODED&JDK_URLS_MACOS=$JDK_URLS_MACOS_ENCODED&JDK_URLS_LINUX=$JDK_URLS_LINUX_ENCODED&BUILD_TYPE=$BUILD_TYPE&PROMOTE=$PROMOTE"
