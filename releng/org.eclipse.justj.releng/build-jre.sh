#!/bin/bash -ex

# These cause a lot of logging in Jenkins which we don't need nor want.
unset JAVA_TOOL_OPTIONS
unset _JAVA_OPTIONS

# Behavior and file names depend on the OS.
if [[ $OSTYPE == darwin* ]]; then
  os=mac
  jdk_suffix="_osx-x64_bin.tar.gz"
  eclipse_suffix="-macosx-cocoa-x86_64.tar.gz"
  jre_suffix="macosx-x86_64"
  jdk_relative_bin_folder="Contents/Home/bin"
  jdk_relative_lib_folder="Contents/Home/lib"
  jdk_relative_vm_arg="Contents/MacOS/libjli.dylib"
  jre_relative_vm_arg="lib/libjli.dylib"
  strip_debug="--strip-debug"
  eclipse_root="Eclipse.app/Contents/Eclipse"
  eclipse_executable="Eclipse.app/Contents/Macos/eclipse"
  unpack200_executable="unpack200"
  if [[ "$JDK_URLS_MACOS" != "" && $# == 0 ]]; then
    urls=$JDK_URLS_MACOS
  fi
elif [[ $OSTYPE == cygwin ||  $OSTYPE = msys ]]; then
  os=win
  jdk_suffix="_windows-x64_bin.zip"
  eclipse_suffix="-win32-x86_64.zip"
  jre_suffix="win32-x86_64"
  jdk_relative_bin_folder="bin"
  jdk_relative_lib_folder="lib"
  jdk_relative_vm_arg="bin"
  jre_relative_vm_arg="bin"
  strip_debug="--strip-debug"
  eclipse_root="eclipse"
  eclipse_executable="eclipse/eclipsec.exe"
  unpack200_executable="unpack200.exe"
  if [[ "$JDK_URLS_WINDOWS" != "" && $# == 0 ]]; then
    urls=$JDK_URLS_WINDOWS
  fi
else
  os=linux

  arch=$(uname -m)
  if [[ "$arch" == aarch64 ]]; then
    jdk_suffix="_linux-aarch64_bin.tar.gz"
    eclipse_suffix="-linux-gtk-aarch64.tar.gz"
    jre_suffix="linux-aarch64"
  else
    jdk_suffix="_linux-x64_bin.tar.gz"
    eclipse_suffix="-linux-gtk-x86_64.tar.gz"
    jre_suffix="linux-x86_64"
  fi

  jdk_relative_bin_folder="bin"
  jdk_relative_lib_folder="lib"
  jdk_relative_vm_arg="bin"
  jre_relative_vm_arg="bin"
  strip_debug="--strip-debug"
  eclipse_root="eclipse"
  eclipse_executable="eclipse/eclipse"
  unpack200_executable="unpack200"

  if [[ "$arch" == aarch64 ]]; then
    if [[ "$JDK_URLS_LINUX" != "" && $# == 0 ]]; then
      urls=$JDK_URLS_LINUX
    fi
  else
    if [[ "$JDK_URLS_LINUX_AARCH64" != "" && $# == 0 ]]; then
      urls=$JDK_URLS_LINUX_AARCH64
    fi
  fi
fi

echo "Processing for os=$os"

# Use a default if the environment has not set the URL.
#
if [[ "$urls" == "" ]]; then
  if [[ $# != 0 ]]; then
    # We deliberately want to split on space because a URL should not have spaces.
    urls=$@
  else
    # Default to Java 15 Open JDK.
    urls="https://download.java.net/java/GA/jdk15.0.1/51f4f36ad4ef43e39d0dfdbaf6549e32/9/GPL/openjdk-15.0.1$jdk_suffix"
  fi
fi

# Loop over all URLs.
for url in $urls; do

echo "Processing '$url'"

# Download the os-specific JDK.
#
file=${url##*/}
if [ ! -f $file ]; then
  echo "Downloading $url"
  curl -O -L -J $url
fi

# Download an os-specific version of Eclipse.
#
eclipse_url="https://download.eclipse.org/eclipse/downloads/drops4/R-4.17-202009021800/eclipse-SDK-4.17$eclipse_suffix"
eclipse_file=${eclipse_url##*/}

if [ ! -f $eclipse_file ]; then
  echo "Downloading $eclipse_url"
  curl -O -L -J $eclipse_url
fi

# Extract the JDK; the folder name is expected to start with jdk-.
#
rm -rf jdk-*
jdk="jdk-*"
if [ ! -d $jdk ]; then
  echo "Unpackaging $file"
  #rm -rf $jdk
  if [[ $os == win ]]; then
    unzip -q $file
  else
    tar -xf $file
  fi
fi

# A sanity test that the JDK has been unpacked.
#
jdk=$(echo jdk-*)
echo "JDK Folder: $jdk"
echo "JDK Version:"
$jdk/$jdk_relative_bin_folder/java -version

# Extract Eclipse; the folder name is expected to be eclipse or Eclipse.app.
#
if [ ! -d $eclipse_root ]; then
  echo "Unpackaging $eclipse_file"
  #rm -rf $eclipse_root
  if [[ $os == win ]]; then
    unzip -q $eclipse_file
  else
    tar -xf $eclipse_file
  fi
fi

# Remove the incubator modules.
#
all_modules=$($jdk/$jdk_relative_bin_folder/java --list-modules | sed "s/@.*//g" | grep -v "jdk.incubator" | tr '\n' ',' | sed 's/,$//')
simrel_modules="java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.naming,java.prefs,java.rmi,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.sql.rowset,java.xml,jdk.crypto.ec,jdk.jdi,jdk.management,jdk.unsupported,jdk.xml.dom"
installer_modules="java.base,java.desktop,java.logging,java.management,java.naming,java.prefs,java.security.jgss,java.sql,java.xml,jdk.xml.dom,jdk.unsupported"


# Create an Ant build file for getting system properties, including ones calculated by Equinox.
#
cat - > build.xml << END
<?xml version="1.0"?>
<project name="SystemProperty" default="build">
  <target name="build">
    <echoproperties/>
  </target>
</project>
END

# Needed for cygwin.
if [[ $OSTYPE == cygwin ]]; then
  for i in $(find eclipse -name "*.exe" -o -name "*.dll"); do
   chmod +x $i
  done
fi

# On Mac this needs to be absolute.
jdk_vm_arg="$jdk/$jdk_relative_vm_arg"
[[ $os == mac ]] && jdk_vm_arg="$PWD/$jdk_vm_arg"

# And then on Mac the launch messes up the user.dir so it can't find the build.xml.
# Also the PWD might contain spaces so we need "" when we use this variable, but then on Linux, an empty string argument is passed and that is used like a class name.
# So always have an argument that might be useless.
user_dir="-Dunused=unused"
[[ $os == mac ]] && user_dir="-Duser.dir=$PWD"

# Capture all the system properties.
$eclipse_executable -application org.eclipse.ant.core.antRunner -nosplash -emacs -vm "$jdk_vm_arg" -vmargs "$user_dir" > all.properties

# Determine the Java version from the system properties.
java_version=$(grep "^java.version=" all.properties | sed 's/^.*=//;s/\r//')
echo "Java Version '$java_version'"

# Compute the name prefix depending on the vendor and VM.
if grep "^java.vendor.version=" all.properties | grep -q "AdoptOpenJDK"; then
  vendor_url="https://adoptopenjdk.net/"
  if grep "OpenJ9" all.properties; then
    vendor_label="AdoptOpenJDK J9"
    vendor_prefix="adoptopenjdk.j9"
  else
    vendor_label="AdoptOpenJDK Hotspot"
    vendor_prefix="adoptopenjdk.hotspot"
  fi
else
  vendor_url="https://jdk.java.net/"
  vendor_label="OpenJDK Hotspot"
  vendor_prefix="openjdk.hotspot"
fi

echo "Vendor prefix: $vendor_prefix-$java_version-$jre_suffix"

# These are the tuples for which we want to generate JREs.
jres=(

"$vendor_prefix.jre.base"
  "JRE Base"
  "Provides the minimal modules needed to launch Equinox without reflection warnings."
  java.base,java.xml,jdk.unsupported,jdk.jdwp.agent
  "--compress=2"
  filter

"$vendor_prefix.jre.base.stripped"
  "JRE Base Stripped"
  "Provides the minimal modules needed to launch Equinox without reflection warnings, stripped of debug information."
  java.base,java.xml,jdk.unsupported
  "--compress=2 $strip_debug"
  false

"$vendor_prefix.jre.full"
  "JRE Complete"
  "Provides the complete set of modules of the JDK, excluding incubators."
  $all_modules
  "--compress=2"
  true

"$vendor_prefix.jre.full.stripped"
  "JRE Complete Stripped"
  "Provides the complete set of modules of the JDK, excluding incubators, stripped of debug information."
  $all_modules
  "--compress=2 $strip_debug"
  false

"$vendor_prefix.jre.minimal"
  "JRE Minimal"
  "Provides the minimal modules needed to satisfy all of the bundles of the simultaneous release."
  $simrel_modules,jdk.jdwp.agent
  "--compress=2"
  filter

"$vendor_prefix.jre.minimal.stripped"
  "JRE Minimal Stripped"
  "Provides the minimal modules needed to satisfy all of the bundles of the simultaneous release, stripped of debug information."
  $simrel_modules
  "--compress=2 $strip_debug"
  false

)

# Iterate over the tuples.
for ((i=0; i<${#jres[@]}; i+=6)); do

  jre_name=${jres[i]}
  jre_label="$vendor_label ${jres[i+1]}"
  jre_description="${jres[i+2]}"
  jre_folder="org.eclipse.justj.$jre_name-$java_version-$jre_suffix"
  rm -rf $jre_folder
  modules=${jres[i+3]}
  jlink_args=${jres[i+4]}
  include_source=${jres[i+5]}

  # Generate the JRE using jlink from the JDK.
  echo "Generating: $jre_folder"
  $jdk/$jdk_relative_bin_folder/jlink --add-modules=$modules $jlink_args --output $jre_folder
  if [[ -f $jdk/$jdk_relative_bin_folder/$unpack200_executable ]]; then
    cp $jdk/$jdk_relative_bin_folder/$unpack200_executable $jre_folder/bin
  fi

  # Include src.zip if needed
  if [[ "$include_source" = true ]]; then
    echo "Copying src.zip from ${jdk}/${jdk_relative_lib_folder}/src.zip into ${jre_folder}/lib"
    cp $jdk/$jdk_relative_lib_folder/src.zip $jre_folder/lib
  elif [[ "$include_source" == filter ]]; then
    echo "Copying filtered src.zip from ${jdk}/${jdk_relative_lib_folder}/src.zip into ${jre_folder}/lib"
    rm -rf jre-src
    mkdir -p jre-src
    unzip -q ${jdk}/${jdk_relative_lib_folder}/src.zip ${modules//,/\/** }/** -d jre-src
    cd jre-src
    zip -r -9 -q ../src.zip *
    cd -
    mv src.zip $jre_folder/lib
    rm -rf jre-src
  fi

  # Build the -vm arg value.
  jre_vm_arg="$jre_folder/$jre_relative_vm_arg"

  # On Mac it must be absolute.
  if [[ $os == mac ]]; then
    jre_vm_arg="$PWD/$jre_vm_arg"
    # On the older 11 JDK, it was in a different folder.
    if [[ ! -f $jre_vm_arg ]]; then
      jre_relative_vm_arg=lib/jli/libjli.dylib
      jre_vm_arg="$jre_folder/$jre_relative_vm_arg"
      jre_vm_arg="$PWD/$jre_vm_arg"
    fi
  fi

  # Capture the interesting system properties.
  $eclipse_executable -application org.eclipse.ant.core.antRunner -nosplash -emacs -vm "$jre_vm_arg"\
      -vmargs "$user_dir" \
      -Dorg.eclipse.justj.vm.arg="$jre_relative_vm_arg" \
      -Dorg.eclipse.justj.name=$jre_name \
      -Dorg.eclipse.justj.label="$jre_label" \
      -Dorg.eclipse.justj.description="$jre_description" \
      -Dorg.eclipse.justj.modules=$modules \
      -Dorg.eclipse.justj.jlink.args="$jlink_args" \
      -Dorg.eclipse.justj.url.vendor="$vendor_url" \
      -Dorg.eclipse.justj.url.source="$url" |
    grep -E "^org.eclipse.just|^java.class.version|^java.runtime|^java.specification|^java.vendor|^java.version|^java.vm|^org.osgi.framework.system.capabilities|^org.osgi.framework.system.packages|^org.osgi.framework.version|^osgi.arch|^osgi.ws|^osgi.os" |
    sort > $jre_folder/org.eclipse.justj.properties

  # Package up the results without the folder name.
  cd $jre_folder
  tar -cf ../$jre_folder.tar *
  tar -czf ../$jre_folder.tar.gz *
  cd -
done

done
