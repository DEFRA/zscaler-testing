#!/bin/bash

# Script to build Docker images from cloned repositories
# Author: Auto-generated script
# Date: $(date)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPOS_DIR="repos"
ERRORS_FILE="docker_build_errors.txt"
BUILD_LOG_DIR="build_logs"
BUILD_TIMEOUT=600  # 10 minutes timeout for each build

# Global counters
GLOBAL_BUILDS_SUCCESSFUL=0
GLOBAL_BUILDS_FAILED=0

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Docker is installed and running
check_docker() {
    print_info "Checking Docker availability..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "Docker is available and running."
}

# Function to initialize log files
initialize_logs() {
    print_info "Initializing log files..."
    
    # Create build logs directory
    mkdir -p "$BUILD_LOG_DIR"
    
    # Initialize or clear the errors file
    echo "Docker Build Errors Report - $(date)" > "$ERRORS_FILE"
    echo "=================================================" >> "$ERRORS_FILE"
    echo "" >> "$ERRORS_FILE"
    
    print_success "Log files initialized."
}

# Function to find Dockerfiles in a repository
find_dockerfiles() {
    local repo_path=$1
    local dockerfiles=()
    
    # Look for Dockerfile (case-insensitive) in the repository
    while IFS= read -r -d '' dockerfile; do
        dockerfiles+=("$dockerfile")
    done < <(find "$repo_path" -maxdepth 3 -type f \( -iname "dockerfile" -o -iname "dockerfile.*" \) -print0 2>/dev/null)
    
    printf '%s\n' "${dockerfiles[@]}"
}

# Function to build Docker image
build_docker_image() {
    local repo_name=$1
    local dockerfile_path=$2
    local repo_path=$3
    
    # Extract directory containing the Dockerfile
    local dockerfile_dir=$(dirname "$dockerfile_path")
    local dockerfile_name=$(basename "$dockerfile_path")
    
    # Create a unique image name
    local image_name=$(echo "$repo_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9.-]/-/g')
    local timestamp=$(date +%s)
    local full_image_name="${image_name}:build-test-${timestamp}"
    
    print_info "Building Docker image: $full_image_name"
    print_info "Using Dockerfile: $dockerfile_path"
    
    # Create log file for this build
    local current_dir=$(pwd)
    local build_log_file="${current_dir}/${BUILD_LOG_DIR}/${repo_name}_build.log"
    
    # Ensure the build logs directory exists
    mkdir -p "${current_dir}/${BUILD_LOG_DIR}"
    
    # Change to the directory containing the Dockerfile
    cd "$dockerfile_dir" || return 1
    
    # Create log file header
    echo "Build log for $repo_name - $(date)" > "$build_log_file"
    echo "Dockerfile: $dockerfile_path" >> "$build_log_file"
    echo "Image name: $full_image_name" >> "$build_log_file"
    echo "=================================================" >> "$build_log_file"
    
    # Attempt to build the Docker image with live output
    local build_exit_code
    
    print_info "Starting Docker build (live output, ${BUILD_TIMEOUT}s timeout)..."
    echo
    
    if [ "$dockerfile_name" = "Dockerfile" ]; then
        # Standard Dockerfile name - show live output and save to log
        timeout "$BUILD_TIMEOUT" docker build -t "$full_image_name" . 2>&1 | tee -a "$build_log_file"
        build_exit_code=${PIPESTATUS[0]}
    else
        # Custom Dockerfile name - show live output and save to log
        timeout "$BUILD_TIMEOUT" docker build -f "$dockerfile_name" -t "$full_image_name" . 2>&1 | tee -a "$build_log_file"
        build_exit_code=${PIPESTATUS[0]}
    fi
    
    # Check if build was terminated due to timeout
    if [ $build_exit_code -eq 124 ]; then
        echo "Build timed out after ${BUILD_TIMEOUT} seconds" | tee -a "$build_log_file"
    fi
    
    # Add exit code to log file
    echo "" >> "$build_log_file"
    echo "Exit code: $build_exit_code" >> "$build_log_file"
    
    # Return to original directory
    cd - &> /dev/null
    
    if [ $build_exit_code -eq 0 ]; then
        echo
        print_success "Successfully built image: $full_image_name"
        ((GLOBAL_BUILDS_SUCCESSFUL++))
        
        # Clean up the image to save space
        print_info "Removing image to save space..."
        if docker rmi "$full_image_name" &> /dev/null; then
            print_success "Image removed successfully."
        else
            print_warning "Failed to remove image $full_image_name"
        fi
        
        return 0
    else
        echo
        print_error "Failed to build image for $repo_name (Exit code: $build_exit_code)"
        ((GLOBAL_BUILDS_FAILED++))
        
        # Log the error to the errors file (reference to build log)
        {
            echo "Repository: $repo_name"
            echo "Dockerfile: $dockerfile_path"
            echo "Error occurred on: $(date)"
            echo "Exit code: $build_exit_code"
            echo "Detailed build log: $build_log_file"
            echo ""
            echo "================================================="
            echo ""
        } >> "$ERRORS_FILE"
        
        return 1
    fi
}

# Function to process a single repository
process_repository() {
    local repo_name=$1
    local repo_path="${REPOS_DIR}/${repo_name}"
    
    if [ ! -d "$repo_path" ]; then
        print_warning "Repository directory not found: $repo_path"
        return 1
    fi
    
    print_info "Processing repository: $repo_name"
    
    # Find all Dockerfiles in the repository
    local dockerfiles
    dockerfiles=($(find_dockerfiles "$repo_path"))
    
    if [ ${#dockerfiles[@]} -eq 0 ]; then
        print_warning "No Dockerfile found in $repo_name"
        return 1
    fi
    
    print_info "Found ${#dockerfiles[@]} Dockerfile(s) in $repo_name"
    
    local success_count=0
    local error_count=0
    
    # Process each Dockerfile
    for dockerfile in "${dockerfiles[@]}"; do
        print_info "Processing Dockerfile: $dockerfile"
        
        if build_docker_image "$repo_name" "$dockerfile" "$repo_path"; then
            ((success_count++))
        else
            ((error_count++))
        fi
        
        echo  # Add some spacing
    done
    
    # Report results for this repository
    if [ $success_count -gt 0 ] && [ $error_count -eq 0 ]; then
        print_success "Repository $repo_name: All $success_count Docker build(s) successful"
        return 0
    elif [ $success_count -gt 0 ] && [ $error_count -gt 0 ]; then
        print_warning "Repository $repo_name: $success_count successful, $error_count failed"
        return 2  # Mixed results
    else
        print_error "Repository $repo_name: All $error_count Docker build(s) failed"
        return 3  # All failed
    fi
}

# Function to display final summary
display_summary() {
    local total_repos=$1
    local repos_with_dockerfiles=$2
    local repos_processed=$3
    local total_builds_attempted=$4
    local total_builds_successful=$5
    local total_builds_failed=$6
    
    echo
    print_info "=== FINAL SUMMARY ==="
    echo "Total repositories checked: $total_repos"
    echo "Repositories with Dockerfiles: $repos_with_dockerfiles"
    echo "Repositories processed: $repos_processed"
    echo "Total Docker builds attempted: $total_builds_attempted"
    echo "Total successful builds: $total_builds_successful"
    echo "Total failed builds: $total_builds_failed"
    echo
    
    if [ $total_builds_failed -gt 0 ]; then
        print_warning "Build errors have been logged to: $ERRORS_FILE"
    fi
    
    if [ -d "$BUILD_LOG_DIR" ]; then
        print_info "Detailed build logs are available in: $BUILD_LOG_DIR/"
    fi
    
    if [ $total_builds_successful -gt 0 ]; then
        print_success "All successful Docker images have been removed to save space."
    fi
}

# Main function
main() {
    print_info "Starting Docker build process for cloned repositories..."
    echo
    
    # Check prerequisites
    check_docker
    
    # Initialize log files
    initialize_logs
    
    # Check if repos directory exists
    if [ ! -d "$REPOS_DIR" ]; then
        print_error "Repositories directory '$REPOS_DIR' not found."
        print_error "Please run the clone-repos.sh script first."
        exit 1
    fi
    
    # Get list of repositories
    local repositories=()
    while IFS= read -r -d '' repo; do
        repo_name=$(basename "$repo")
        repositories+=("$repo_name")
    done < <(find "$REPOS_DIR" -maxdepth 1 -type d ! -name "$REPOS_DIR" -print0 2>/dev/null)
    
    if [ ${#repositories[@]} -eq 0 ]; then
        print_error "No repositories found in '$REPOS_DIR' directory."
        exit 1
    fi
    
    print_info "Found ${#repositories[@]} repositories to process."
    echo
    
    # Initialize counters
    local total_repos=${#repositories[@]}
    local repos_with_dockerfiles=0
    local repos_processed=0
    local total_builds_attempted=0
    local total_builds_successful=0
    local total_builds_failed=0
    
    # Process each repository
    for repo_name in "${repositories[@]}"; do
        print_info "=== Processing Repository: $repo_name ==="
        
        # Count Dockerfiles in this repo
        local repo_path="${REPOS_DIR}/${repo_name}"
        local dockerfiles
        dockerfiles=($(find_dockerfiles "$repo_path"))
        local dockerfile_count=${#dockerfiles[@]}
        
        if [ $dockerfile_count -gt 0 ]; then
            ((repos_with_dockerfiles++))
            ((total_builds_attempted += dockerfile_count))
            
            # Process the repository
            if process_repository "$repo_name"; then
                ((repos_processed++))
            fi
        else
            print_warning "No Dockerfiles found in $repo_name"
        fi
        
        echo
        echo "================================================="
        echo
    done
    
    # Use global counters for final summary
    total_builds_successful=$GLOBAL_BUILDS_SUCCESSFUL
    total_builds_failed=$GLOBAL_BUILDS_FAILED
    
    # Display final summary
    display_summary "$total_repos" "$repos_with_dockerfiles" "$repos_processed" \
                   "$total_builds_attempted" "$total_builds_successful" "$total_builds_failed"
}

# Run the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
