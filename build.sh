#!/bin/bash

# Script to build all Zulu Tomcat Docker images based on build-config.yaml
# Requires: bash, yq (YAML processor), docker

set -e

echo "Zulu Tomcat Docker Image Builder"
echo "================================"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install it first."
    echo "You can install it using: pip install yq"
    exit 1
fi

# Set BUILD_IMAGES=n to only generate the Dockerfiles and skip the image build.
BUILD_IMAGES=${BUILD_IMAGES:-y}

# Check if Docker is installed
if [[ $BUILD_IMAGES =~ ^[Yy]$ ]] && ! command -v docker &> /dev/null; then
    echo "Error: docker is required but not installed. Please install it first."
    echo "Set BUILD_IMAGES=n to generate the Dockerfiles without building them."
    exit 1
fi

CONFIG_FILE="build-config.yaml"
BUILD_DIR="build"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Read a value from the configuration, mapping a missing key to an empty string
# instead of the literal "null" that yq prints.
config_value() {
    local value
    value=$(yq e "$1" "$CONFIG_FILE")
    if [ "$value" == "null" ]; then
        value=""
    fi
    echo "$value"
}

# Function to generate a Dockerfile for Linux-based distributions
generate_linux_dockerfile() {
    local tomcat_version=$1
    local tomcat_full_version=$2
    local tomcat_url=$3
    local jdk_version=$4
    local distro=$5
    local output_dir="${BUILD_DIR}/${distro}/${tomcat_version}-jdk${jdk_version}"

    # Create directory if it doesn't exist
    mkdir -p "$output_dir"

    # Get distribution-specific configuration
    local base_image=$(config_value ".distributions.${distro}.base_image")
    local install_cmd=$(config_value ".distributions.${distro}.package_manager.install")
    local remove_cmd=$(config_value ".distributions.${distro}.package_manager.remove")
    local cleanup_cmd=$(config_value ".distributions.${distro}.package_manager.cleanup")
    local download_tool=$(config_value ".distributions.${distro}.download_tool")
    local download_flags=$(config_value ".distributions.${distro}.download_flags")
    local archive_ext=$(config_value ".distributions.${distro}.archive_ext")
    local extract_cmd=$(config_value ".distributions.${distro}.extract_cmd")
    local file_cleanup_cmd=$(config_value ".distributions.${distro}.cleanup_cmd")
    local run_cmd=$(config_value ".distributions.${distro}.run_cmd")
    local multi_stage=$(config_value ".distributions.${distro}.multi_stage")

    # A distribution whose base image already ships the download tool configures no
    # package_manager at all, so both the install and the removal step are omitted.
    # The ampersands stay backslash-escaped: an unescaped & in a bash substitution
    # replacement expands to the matched text instead of staying literal.
    local install_line=""
    if [ -n "$install_cmd" ]; then
        install_line="${install_cmd} ${download_tool} \&\& "
    fi

    local cleanup_line=""
    if [ -n "$remove_cmd" ]; then
        cleanup_line=" \&\& ${remove_cmd} ${download_tool}"
        if [ -n "$cleanup_cmd" ]; then
            cleanup_line="${cleanup_line} \&\& ${cleanup_cmd}"
        fi
    fi

    # Handle special case for distroless (multi-stage build)
    if [ "$multi_stage" == "true" ]; then
        local builder_image=$(config_value ".distributions.${distro}.builder_image")
        local entrypoint=$(config_value ".distributions.${distro}.entrypoint")

        # Read the template file
        local template_content=$(cat "templates/linux-distroless/Dockerfile.template")

        # Replace variables in the template
        template_content=${template_content//\$\{builder_image\}/$builder_image}
        template_content=${template_content//\$\{base_image\}/$base_image}
        template_content=${template_content//\$\{jdk_version\}/$jdk_version}
        template_content=${template_content//\$\{install_line\}/$install_line}
        template_content=${template_content//\$\{download_tool\}/$download_tool}
        template_content=${template_content//\$\{download_flags\}/$download_flags}
        template_content=${template_content//\$\{tomcat_url\}/$tomcat_url}
        template_content=${template_content//\$\{archive_ext\}/$archive_ext}
        template_content=${template_content//\$\{extract_cmd\}/$extract_cmd}
        template_content=${template_content//\$\{file_cleanup_cmd\}/$file_cleanup_cmd}
        template_content=${template_content//\$\{entrypoint\}/$entrypoint}

        # Write the processed template to the Dockerfile
        echo "$template_content" > "$output_dir/Dockerfile"
    else
        # Read the template file
        local template_content=$(cat "templates/linux/Dockerfile.template")

        # Replace variables in the template
        template_content=${template_content//\$\{base_image\}/$base_image}
        template_content=${template_content//\$\{jdk_version\}/$jdk_version}
        template_content=${template_content//\$\{install_line\}/$install_line}
        template_content=${template_content//\$\{download_tool\}/$download_tool}
        template_content=${template_content//\$\{download_flags\}/$download_flags}
        template_content=${template_content//\$\{tomcat_url\}/$tomcat_url}
        template_content=${template_content//\$\{archive_ext\}/$archive_ext}
        template_content=${template_content//\$\{extract_cmd\}/$extract_cmd}
        template_content=${template_content//\$\{file_cleanup_cmd\}/$file_cleanup_cmd}
        template_content=${template_content//\$\{cleanup_line\}/$cleanup_line}
        template_content=${template_content//\$\{run_cmd\}/$run_cmd}

        # Write the processed template to the Dockerfile
        echo "$template_content" > "$output_dir/Dockerfile"
    fi

    echo "Generated Dockerfile for ${distro}/${tomcat_version}-jdk${jdk_version}"
}

# Process each Tomcat version and distribution combination
echo "Generating Dockerfiles..."

# Get all Tomcat versions
tomcat_versions=$(yq e '.tomcat | keys | .[]' "$CONFIG_FILE")

# Get all distributions
distributions=$(yq e '.distributions | keys | .[]' "$CONFIG_FILE")

for tomcat_version in $tomcat_versions; do
    tomcat_full_version=$(yq e ".tomcat.\"${tomcat_version}\".version" "$CONFIG_FILE")
    tomcat_url=$(yq e ".tomcat.\"${tomcat_version}\".url" "$CONFIG_FILE")
    jdk_versions=$(yq e ".tomcat.\"${tomcat_version}\".jdk[]" "$CONFIG_FILE")

    echo "Processing Tomcat ${tomcat_version} (${tomcat_full_version}) with JDK $(echo $jdk_versions | tr ' ' ',')"

    for jdk_version in $jdk_versions; do
        for distro in $distributions; do
            # Check if this distribution excludes the current JDK version
            excluded_jdk_versions=$(yq e ".distributions.${distro}.excluded_jdk_versions[]" "$CONFIG_FILE")
            skip_build=false
            for excluded_jdk_version in $excluded_jdk_versions; do
                if [ "$jdk_version" == "$excluded_jdk_version" ]; then
                    skip_build=true
                    break
                fi
            done

            if [ "$skip_build" == "true" ]; then
                echo "Skipping ${distro}/${tomcat_version}-jdk${jdk_version} (JDK ${jdk_version} is excluded for ${distro})"
                continue
            fi

            generate_linux_dockerfile "$tomcat_version" "$tomcat_full_version" "$tomcat_url" "$jdk_version" "$distro"
        done
    done
done

echo "All Dockerfiles generated successfully."

# Build all Docker images
if [[ $BUILD_IMAGES =~ ^[Yy]$ ]]; then
    echo "Building Docker images..."
    echo "This may take a while..."

    for tomcat_version in $tomcat_versions; do
        jdk_versions=$(yq e ".tomcat.\"${tomcat_version}\".jdk[]" "$CONFIG_FILE")

        for jdk_version in $jdk_versions; do
            for distro in $distributions; do
                image_name="zulu-tomcat-${distro}:${tomcat_version}-jdk${jdk_version}"
                dockerfile_path="${BUILD_DIR}/${distro}/${tomcat_version}-jdk${jdk_version}/Dockerfile"
                if [ ! -f "$dockerfile_path" ]; then
                  continue
                fi

                echo "Building ${image_name}..."
                docker build -t "$image_name" -f "$dockerfile_path" .

                if [ $? -eq 0 ]; then
                    echo "Successfully built ${image_name}"
                else
                    echo "Failed to build ${image_name}"
                fi
            done
        done
    done

    echo "All Docker images built successfully."
else
    echo "Skipping Docker image build."
    echo "You can build the images later by running 'docker build' commands manually."
fi

echo "Done!"
