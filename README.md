# Zulu Tomcat Docker Images

This repository contains Dockerfiles for building Tomcat images with Azul Zulu JDK across multiple operating systems and Tomcat versions.

## Supported Configurations

### Tomcat Versions
- Tomcat 9.0 with JDK 8
- Tomcat 10.1 with JDK 11
- Tomcat 11.0 with JDK 21

### Operating Systems/Distributions
- Alpine Linux
- CentOS
- Debian
- Ubuntu
- Distroless (minimal container with multi-stage build)

## Build Configuration

All build configurations are centralized in the `build-config.yaml` file. This file contains:

- Tomcat version information and download URLs
- JDK version mappings
- OS/distribution-specific configurations
- Package manager commands
- Special configurations for different environments

## Building Docker Images

### Prerequisites

- Docker installed and running
- For Linux/macOS: Bash shell and `yq` YAML processor

### Building All Images

#### On Linux/macOS:

```bash
# Make the script executable
chmod +x build.sh

# Run the build script
./build.sh
```

The script will:
1. Generate Dockerfiles for all combinations of Tomcat versions and OS/distributions
2. Ask if you want to build all Docker images
3. If confirmed, build all Docker images

### Building Specific Images

If you want to build only specific images, you can use the generated Dockerfiles directly:

```bash
# Example: Build alpine Tomcat 9.0 with JDK 8
docker build -t zulu-tomcat-alpine:9.0-jdk8 -f build/alpine/9.0-jdk8/Dockerfile .
```

## Pushing Docker Images to Docker Hub

After building the Docker images, you can push them to Docker Hub using the provided scripts.

### Prerequisites

- Docker installed and running
- Docker Hub account
- For Linux/macOS: Bash shell and `yq` YAML processor

### Pushing All Images

#### On Linux/macOS:

```bash
# Make the script executable
chmod +x docker-push.sh

# Push to default organization (azul)
./docker-push.sh

# Push to specific organization or username
./docker-push.sh myorganization

# Push with password provided as argument (not recommended for security reasons)
./docker-push.sh myorganization mypassword
```

The script will:
1. Authenticate with Docker Hub (if not already authenticated)
2. Tag all locally built images with your Docker Hub organization/username
3. Push all tagged images to Docker Hub

### Pushing Specific Images

If you want to push only specific images, you can use Docker commands directly:

```bash
# Example: Tag and push alpine Tomcat 9.0 with JDK 8
docker tag zulu-tomcat-alpine:9.0-jdk8 myorganization/zulu-tomcat-alpine:9.0-jdk8
docker push myorganization/zulu-tomcat-alpine:9.0-jdk8
```

## Customizing Builds

To customize the builds:

1. Edit the `build-config.yaml` file to modify versions, URLs, or OS-specific configurations
2. Modify the Dockerfile templates in the `templates` directory if needed:
   - `templates/linux/Dockerfile.template` - Template for standard Linux distributions
   - `templates/linux-distroless/Dockerfile.template` - Template for distroless multi-stage builds
3. Run the build script again to regenerate Dockerfiles and rebuild images

## Adding New Versions

To add a new Tomcat version:

1. Add a new entry to the `tomcat` section in `build-config.yaml`
2. Specify the version, download URL, and JDK version
3. Run the build script to generate Dockerfiles for the new version

Example:

```yaml
tomcat:
  "12.0":
    version: "12.0.0"
    url: "https://dlcdn.apache.org/tomcat/tomcat-12/v12.0.0/bin/apache-tomcat-12.0.0"
    jdk: "21"
```

## Adding New Distributions

To add a new OS/distribution:

1. Add a new entry to the `distributions` section in `build-config.yaml`
2. Specify all required configuration parameters
3. Run the build script to generate Dockerfiles for the new distribution

## License

This project is licensed under the same license as Tomcat and Azul Zulu JDK.
