# Zscaler Testing Repository

This repository is intended to test for potential conflicts with Zscaler in software development environments. It contains automated scripts to systematically test Docker builds and Node.js package installations across a comprehensive collection of DEFRA repositories to identify any issues that may arise when using Zscaler network security solutions.

## Overview

Zscaler is a cloud-based security platform that can sometimes interfere with development workflows, particularly around:
- SSL/TLS certificate validation
- Network connectivity to package registries (npm, Docker Hub, etc.)
- Proxy configurations
- DNS resolution

This testing suite helps identify and document such issues by running realistic development scenarios across a large number of real-world repositories.

## Methodology

The testing approach follows a systematic three-phase methodology:

### 1. Repository Discovery and Cloning
Retrieve all public images from Docker Hub (specifically from the `defradigital` organization) including those for real CDP (Core Delivery Platform) hosted services, then clone the corresponding source repositories from the DEFRA GitHub organization.

### 2. Docker Build Testing
For all repositories containing a Dockerfile, build the Docker image and report any issues that may arise due to network restrictions, certificate validation problems, or other Zscaler-related interference.

### 3. Node.js Dependency Installation Testing
For all Node.js repositories (containing `package.json` files), run `npm install` and report any issues related to package registry access, SSL certificate validation, or network connectivity problems.

## Scripts

### clone-repos.sh
**Purpose**: Discovers and clones repositories for testing

**Features**:
- Fetches repository list from Docker Hub API (`https://hub.docker.com/v2/repositories/defradigital`)
- Checks for corresponding repositories in the DEFRA GitHub organization
- Clones repositories that exist in both Docker Hub and GitHub
- Comprehensive logging of successful clones and missing repositories

**Usage**:
```bash
./clone-repos.sh
```

**Dependencies**:
- `curl` - For API requests
- `jq` - For JSON processing
- `git` - For repository cloning

### build-docker.sh
**Purpose**: Tests Docker image building across all cloned repositories

**Features**:
- Automatically discovers Dockerfiles in all cloned repositories
- Builds Docker images with live output showing real-time progress
- 600-second timeout protection to prevent hanging builds
- Comprehensive error logging and reporting
- Automatic cleanup of successfully built images to save disk space
- Detailed build logs saved to `docker_build_logs/` directory

**Usage**:
```bash
./build-docker.sh
```

**Log Files**:
- `docker_build_summary.log` - Summary of all build attempts
- `docker_build_errors.txt` - Error report with references to detailed logs
- `docker_build_logs/` - Directory containing detailed build logs for each repository

**Dependencies**:
- Docker daemon running
- Sufficient disk space for temporary image storage

### npm-install.sh
**Purpose**: Tests Node.js package installation across all repositories

**Features**:
- Automatically discovers `package.json` files in all cloned repositories
- Runs `npm install` with live output showing real-time progress
- 600-second timeout protection per installation
- Comprehensive error logging and reporting
- Detailed installation logs for troubleshooting

**Usage**:
```bash
./npm-install.sh
```

**Log Files**:
- `npm_install_summary.log` - Summary of all installation attempts
- `npm_install_errors.txt` - Error report with references to detailed logs
- `npm_install_logs/` - Directory containing detailed installation logs

**Dependencies**:
- Node.js and npm installed
- Network access to npm registry

## Common Zscaler Issues

Based on testing, the following issues may be encountered when using Zscaler:

### SSL Certificate Issues
- **Symptom**: SSL certificate validation failures during package downloads
- **Example**: Alpine package manager failing with certificate errors
- **Solution**: Configure proper certificate handling or certificate pinning bypass

### Network Connectivity Issues
- **Symptom**: Timeouts or connection refused errors to registries
- **Example**: npm registry connection failures
- **Solution**: Configure proxy settings and firewall rules

### DNS Resolution Problems
- **Symptom**: Unable to resolve package registry domains
- **Example**: Docker Hub or npm registry DNS failures
- **Solution**: Configure proper DNS settings and domain whitelisting

## Running the Complete Test Suite

To run the complete testing methodology:

1. **Clone repositories**:
   ```bash
   ./clone-repos.sh
   ```

2. **Test Docker builds**:
   ```bash
   ./build-docker.sh
   ```

3. **Test npm installations**:
   ```bash
   ./npm-install.sh
   ```

4. **Review results**:
   ```bash
   # Check summaries
   cat docker_build_summary.log
   cat npm_install_summary.log
   
   # Check error reports
   cat docker_build_errors.txt
   cat npm_install_errors.txt
   ```

## Results Interpretation

### Successful Operations
- Operations that complete without errors indicate no Zscaler interference
- These represent baseline functionality that should continue to work

### Failed Operations
- Failed builds or installations may indicate Zscaler-related issues
- Review detailed logs to determine if failures are network/security related
- Common patterns in failures can help identify systematic Zscaler configuration issues

## Troubleshooting

If you encounter issues:

1. **Check network connectivity**: Ensure basic internet access is working
2. **Verify Docker daemon**: Ensure Docker is running for build tests
3. **Check Node.js/npm**: Ensure Node.js and npm are properly installed
4. **Review logs**: Check detailed logs in the respective log directories
5. **Proxy configuration**: Ensure Zscaler proxy settings are properly configured for development tools

## Contributing

When adding new test scenarios:
1. Follow the established logging patterns
2. Include timeout protection for long-running operations
3. Provide both summary and detailed logging
4. Update this README with new methodologies or findings

---

*This testing suite helps ensure development workflows remain functional when using Zscaler network security solutions.*
