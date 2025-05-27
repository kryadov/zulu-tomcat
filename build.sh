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

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: docker is required but not installed. Please install it first."
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
    local base_image=$(yq e ".distributions.${distro}.base_image" "$CONFIG_FILE")
    local install_cmd=$(yq e ".distributions.${distro}.package_manager.install" "$CONFIG_FILE")
    local remove_cmd=$(yq e ".distributions.${distro}.package_manager.remove" "$CONFIG_FILE")
    local cleanup_cmd=$(yq e ".distributions.${distro}.package_manager.cleanup" "$CONFIG_FILE")
    local download_tool=$(yq e ".distributions.${distro}.download_tool" "$CONFIG_FILE")
    local archive_ext=$(yq e ".distributions.${distro}.archive_ext" "$CONFIG_FILE")
    local extract_cmd=$(yq e ".distributions.${distro}.extract_cmd" "$CONFIG_FILE")
    local file_cleanup_cmd=$(yq e ".distributions.${distro}.cleanup_cmd" "$CONFIG_FILE")
    local run_cmd=$(yq e ".distributions.${distro}.run_cmd" "$CONFIG_FILE")
    local multi_stage=$(yq e ".distributions.${distro}.multi_stage" "$CONFIG_FILE")

    # Handle special case for distroless (multi-stage build)
    if [ "$multi_stage" == "true" ]; then
        local builder_image=$(yq e ".distributions.${distro}.builder_image" "$CONFIG_FILE")
        local entrypoint=$(yq e ".distributions.${distro}.entrypoint" "$CONFIG_FILE")

        # Read the template file
        local template_content=$(cat "templates/linux-distroless/Dockerfile.template")

        # Replace variables in the template
        template_content=${template_content//\$\{builder_image\}/$builder_image}
        template_content=${template_content//\$\{base_image\}/$base_image}
        template_content=${template_content//\$\{jdk_version\}/$jdk_version}
        template_content=${template_content//\$\{install_cmd\}/$install_cmd}
        template_content=${template_content//\$\{download_tool\}/$download_tool}
        template_content=${template_content//\$\{tomcat_url\}/$tomcat_url}
        template_content=${template_content//\$\{archive_ext\}/$archive_ext}
        template_content=${template_content//\$\{extract_cmd\}/$extract_cmd}
        template_content=${template_content//\$\{file_cleanup_cmd\}/$file_cleanup_cmd}
        template_content=${template_content//\$\{entrypoint\}/$entrypoint}

        # Write the processed template to the Dockerfile
        echo "$template_content" > "$output_dir/Dockerfile"
    else
        # Standard Linux Dockerfile
        local cleanup_commands=""
        if [ -n "$remove_cmd" ]; then
            cleanup_commands="${remove_cmd} ${download_tool}"
            if [ -n "$cleanup_cmd" ]; then
                cleanup_commands="${cleanup_commands} \&\& ${cleanup_cmd}"
            fi
        fi

        # Read the template file
        local template_content=$(cat "templates/linux/Dockerfile.template")

        # Replace variables in the template
        template_content=${template_content//\$\{base_image\}/$base_image}
        template_content=${template_content//\$\{jdk_version\}/$jdk_version}
        template_content=${template_content//\$\{install_cmd\}/$install_cmd}
        template_content=${template_content//\$\{download_tool\}/$download_tool}
        template_content=${template_content//\$\{tomcat_url\}/$tomcat_url}
        template_content=${template_content//\$\{archive_ext\}/$archive_ext}
        template_content=${template_content//\$\{extract_cmd\}/$extract_cmd}
        template_content=${template_content//\$\{file_cleanup_cmd\}/$file_cleanup_cmd}
        # Handle cleanup_commands with proper escaping to avoid issues with special characters
        if [ -n "$cleanup_commands" ]; then
            template_content=${template_content//\$\{cleanup_commands\}/$cleanup_commands}
        else
            # If cleanup_commands is empty, just remove the variable reference
            template_content=${template_content//\$\{cleanup_commands\}/}
        fi
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

for tomcat_version in $tomcat_versions; do
    tomcat_full_version=$(yq e ".tomcat.\"${tomcat_version}\".version" "$CONFIG_FILE")
    tomcat_url=$(yq e ".tomcat.\"${tomcat_version}\".url" "$CONFIG_FILE")
    jdk_version=$(yq e ".tomcat.\"${tomcat_version}\".jdk" "$CONFIG_FILE")

    echo "Processing Tomcat ${tomcat_version} (${tomcat_full_version}) with JDK ${jdk_version}"

    # Get all distributions
    distributions=$(yq e '.distributions | keys | .[]' "$CONFIG_FILE")

    for distro in $distributions; do
        # Check if this distribution has excluded JDK versions
        excluded_jdk_versions=$(yq e ".distributions.${distro}.excluded_jdk_version // 0" "$CONFIG_FILE")
        # Check if current JDK version is in the excluded list
        skip_build=false
        if [ "$jdk_version" == "$excluded_jdk_versions" ]; then
            echo "Skipping ${distro}/${tomcat_version}-jdk${jdk_version} (JDK ${jdk_version} is excluded for ${distro})"
            skip_build=true
            break
        fi

        if [ "$skip_build" == "false" ]; then
            generate_linux_dockerfile "$tomcat_version" "$tomcat_full_version" "$tomcat_url" "$jdk_version" "$distro"
        fi
    done
done

echo "All Dockerfiles generated successfully."

# Build all Docker images
echo "Building Docker images..."
echo "This may take a while..."

# Ask if user wants to build all images
# read -p "Do you want to build all Docker images now? (y/n) " -n 1 -r
# echo
REPLY=y
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for tomcat_version in $tomcat_versions; do
        jdk_version=$(yq e ".tomcat.\"${tomcat_version}\".jdk" "$CONFIG_FILE")

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

    echo "All Docker images built successfully."
else
    echo "Skipping Docker image build."
    echo "You can build the images later by running 'docker build' commands manually."
fi

echo "Done!"
