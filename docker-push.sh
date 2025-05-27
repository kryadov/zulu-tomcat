#!/bin/bash

# Script to push Zulu Tomcat Docker images to Docker Hub
# Requires: bash, yq (YAML processor), docker

set -e

echo "Zulu Tomcat Docker Hub Push Tool"
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

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Default Docker Hub organization/username
DEFAULT_ORG="azul"

# Parse command line arguments
DOCKER_HUB_ORG=${1:-$DEFAULT_ORG}
DOCKER_HUB_PASSWORD=$2

# Display usage information if help flag is provided
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Usage: $0 [DOCKER_HUB_ORG] [DOCKER_HUB_PASSWORD]"
    echo ""
    echo "Arguments:"
    echo "  DOCKER_HUB_ORG      Docker Hub organization or username (default: $DEFAULT_ORG)"
    echo "  DOCKER_HUB_PASSWORD Docker Hub password (optional, will prompt if not provided)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Push to $DEFAULT_ORG organization, prompt for password"
    echo "  $0 myusername       # Push to myusername, prompt for password"
    echo "  $0 myorg mypassword # Push to myorg using provided password"
    exit 0
fi

echo "Will push images to Docker Hub organization/username: $DOCKER_HUB_ORG"

# Login to Docker Hub if password is provided
if [ -n "$DOCKER_HUB_PASSWORD" ]; then
    echo "Logging in to Docker Hub as $DOCKER_HUB_ORG..."
    echo "$DOCKER_HUB_PASSWORD" | docker login --username "$DOCKER_HUB_ORG" --password-stdin
else
    # Check if already logged in
    if ! docker info | grep -q "Username: $DOCKER_HUB_ORG"; then
        echo "Please login to Docker Hub:"
        docker login --username "$DOCKER_HUB_ORG"
    fi
fi

# Get all Tomcat versions
tomcat_versions=$(yq e '.tomcat | keys | .[]' "$CONFIG_FILE")

# Get all distributions
distributions=$(yq e '.distributions | keys | .[]' "$CONFIG_FILE")

# Ask if user wants to push all images
read -p "Do you want to push all Docker images to Docker Hub? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    for tomcat_version in $tomcat_versions; do
        jdk_version=$(yq e ".tomcat.\"${tomcat_version}\".jdk" "$CONFIG_FILE")
        
        for distro in $distributions; do
            local_image="zulu-tomcat-${distro}:${tomcat_version}-jdk${jdk_version}"
            remote_image="${DOCKER_HUB_ORG}/zulu-tomcat-${distro}:${tomcat_version}-jdk${jdk_version}"
            
            # Check if image exists locally
            if docker image inspect "$local_image" &> /dev/null; then
                echo "Tagging ${local_image} as ${remote_image}..."
                docker tag "$local_image" "$remote_image"
                
                echo "Pushing ${remote_image} to Docker Hub..."
                docker push "$remote_image"
                
                if [ $? -eq 0 ]; then
                    echo "Successfully pushed ${remote_image}"
                else
                    echo "Failed to push ${remote_image}"
                fi
            else
                echo "Warning: Image ${local_image} not found locally, skipping."
            fi
        done
    done
    
    echo "All Docker images pushed successfully."
else
    echo "Skipping Docker image push."
    echo "You can push the images later by running 'docker push' commands manually."
fi

echo "Done!"