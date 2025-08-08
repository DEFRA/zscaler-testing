#!/bin/bash

# Script to requeue failed Docker builds from existing build logs
# This script analyzes build logs and creates a queue file for retrying failed builds
# Author: Auto-generated script
# Date: $(date)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_LOG_DIR="build_logs"
QUEUE_FILE="docker_build_queue.txt"
PROGRESS_FILE="docker_build_progress.txt"
REPOS_DIR="repos"

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

# Function to extract repository name and dockerfile path from a build log
extract_build_info() {
    local log_file=$1
    local repo_name=""
    local dockerfile_path=""
    
    # Extract from the log file header
    while IFS= read -r line; do
        if [[ $line =~ ^Build\ log\ for\ (.+)\ -\ .* ]]; then
            repo_name="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^Dockerfile:\ (.+)$ ]]; then
            dockerfile_path="${BASH_REMATCH[1]}"
            break
        fi
    done < "$log_file"
    
    if [ -n "$repo_name" ] && [ -n "$dockerfile_path" ]; then
        echo "${repo_name}|${dockerfile_path}"
        return 0
    fi
    
    return 1
}

# Function to verify if repository and dockerfile still exist
verify_build_target() {
    local repo_name=$1
    local dockerfile_path=$2
    
    # Check if repository exists
    if [ ! -d "${REPOS_DIR}/${repo_name}" ]; then
        print_warning "Repository directory not found: ${REPOS_DIR}/${repo_name}"
        return 1
    fi
    
    # Check if dockerfile exists
    if [ ! -f "$dockerfile_path" ]; then
        print_warning "Dockerfile not found: $dockerfile_path"
        return 1
    fi
    
    return 0
}

# Function to create requeue file from failed build logs
create_requeue() {
    print_info "Analyzing failed build logs in $BUILD_LOG_DIR..."
    
    if [ ! -d "$BUILD_LOG_DIR" ]; then
        print_error "Build logs directory '$BUILD_LOG_DIR' not found."
        print_error "It appears no Docker builds have been attempted yet."
        exit 1
    fi
    
    # Count total log files
    local total_logs=$(ls "$BUILD_LOG_DIR"/*.log 2>/dev/null | wc -l)
    
    if [ $total_logs -eq 0 ]; then
        print_error "No build log files found in '$BUILD_LOG_DIR'."
        print_error "It appears no Docker builds have failed."
        exit 1
    fi
    
    print_info "Found $total_logs failed build log files"
    
    # Backup existing queue and progress files if they exist
    if [ -f "$QUEUE_FILE" ]; then
        local backup_queue="${QUEUE_FILE}.backup.$(date +%s)"
        print_warning "Existing queue file found. Backing up to: $backup_queue"
        cp "$QUEUE_FILE" "$backup_queue"
    fi
    
    if [ -f "$PROGRESS_FILE" ]; then
        local backup_progress="${PROGRESS_FILE}.backup.$(date +%s)"
        print_warning "Existing progress file found. Backing up to: $backup_progress"
        cp "$PROGRESS_FILE" "$backup_progress"
    fi
    
    # Clear existing queue and progress files
    > "$QUEUE_FILE"
    > "$PROGRESS_FILE"
    
    local processed_logs=0
    local valid_targets=0
    local invalid_targets=0
    
    print_info "Processing build logs to extract repository and Dockerfile information..."
    
    # Process each build log file
    for log_file in "$BUILD_LOG_DIR"/*.log; do
        if [ ! -f "$log_file" ]; then
            continue
        fi
        
        ((processed_logs++))
        local log_basename=$(basename "$log_file")
        
        # Extract build information
        local build_info
        if build_info=$(extract_build_info "$log_file"); then
            local repo_name=$(echo "$build_info" | cut -d'|' -f1)
            local dockerfile_path=$(echo "$build_info" | cut -d'|' -f2)
            
            print_info "[$processed_logs/$total_logs] Processing: $repo_name"
            
            # Verify the repository and dockerfile still exist
            if verify_build_target "$repo_name" "$dockerfile_path"; then
                echo "$build_info" >> "$QUEUE_FILE"
                ((valid_targets++))
                print_success "  ✓ Added to queue: $repo_name -> $(basename "$dockerfile_path")"
            else
                ((invalid_targets++))
                print_warning "  ✗ Skipped (missing files): $repo_name -> $(basename "$dockerfile_path")"
            fi
        else
            ((invalid_targets++))
            print_error "  ✗ Failed to extract build info from: $log_basename"
        fi
    done
    
    echo
    print_info "=== REQUEUE SUMMARY ==="
    echo "Total build logs processed: $processed_logs"
    echo "Valid targets added to queue: $valid_targets"
    echo "Invalid/missing targets skipped: $invalid_targets"
    
    if [ $valid_targets -gt 0 ]; then
        print_success "Successfully created requeue file with $valid_targets failed builds"
        print_info "Queue file: $QUEUE_FILE"
        print_info "You can now run './build-docker.sh' to retry the failed builds"
        
        echo
        print_info "Preview of queued builds:"
        echo "=========================="
        head -10 "$QUEUE_FILE" | while IFS='|' read -r repo dockerfile; do
            echo "  • $repo -> $(basename "$dockerfile")"
        done
        
        if [ $valid_targets -gt 10 ]; then
            echo "  ... and $((valid_targets - 10)) more"
        fi
        
    else
        print_warning "No valid build targets found to requeue"
        print_info "This could mean:"
        print_info "  - All repositories/Dockerfiles have been moved or deleted"
        print_info "  - The build log format has changed"
        print_info "  - All previous builds were actually successful"
        
        # Clean up empty files
        rm -f "$QUEUE_FILE" "$PROGRESS_FILE"
    fi
}

# Function to show current queue status
show_queue_status() {
    if [ ! -f "$QUEUE_FILE" ]; then
        print_info "No queue file found. Run with --create to create one from failed builds."
        return 0
    fi
    
    local queue_count=$(wc -l < "$QUEUE_FILE" 2>/dev/null || echo 0)
    local progress_count=$(wc -l < "$PROGRESS_FILE" 2>/dev/null || echo 0)
    
    print_info "=== QUEUE STATUS ==="
    echo "Remaining builds in queue: $queue_count"
    echo "Completed builds: $progress_count"
    
    if [ $queue_count -gt 0 ]; then
        echo
        print_info "Next builds in queue:"
        echo "===================="
        head -5 "$QUEUE_FILE" | while IFS='|' read -r repo dockerfile; do
            echo "  • $repo -> $(basename "$dockerfile")"
        done
        
        if [ $queue_count -gt 5 ]; then
            echo "  ... and $((queue_count - 5)) more"
        fi
    fi
    
    if [ $progress_count -gt 0 ]; then
        echo
        print_info "Recent completed builds:"
        echo "======================="
        tail -5 "$PROGRESS_FILE" | while IFS='|' read -r timestamp repo dockerfile status; do
            local status_icon="✓"
            local status_color=$GREEN
            if [ "$status" = "FAILED" ]; then
                status_icon="✗"
                status_color=$RED
            fi
            echo -e "  ${status_color}${status_icon}${NC} $repo -> $(basename "$dockerfile") [$status]"
        done
    fi
}

# Function to clear queue and progress files
clear_queue() {
    local confirm=""
    print_warning "This will clear the current build queue and progress files."
    read -p "Are you sure you want to continue? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if [ -f "$QUEUE_FILE" ] || [ -f "$PROGRESS_FILE" ]; then
            # Create backups before clearing
            local timestamp=$(date +%s)
            if [ -f "$QUEUE_FILE" ]; then
                cp "$QUEUE_FILE" "${QUEUE_FILE}.cleared.${timestamp}"
                print_info "Backed up queue file to: ${QUEUE_FILE}.cleared.${timestamp}"
            fi
            if [ -f "$PROGRESS_FILE" ]; then
                cp "$PROGRESS_FILE" "${PROGRESS_FILE}.cleared.${timestamp}"
                print_info "Backed up progress file to: ${PROGRESS_FILE}.cleared.${timestamp}"
            fi
            
            # Clear the files
            rm -f "$QUEUE_FILE" "$PROGRESS_FILE"
            print_success "Queue and progress files cleared successfully"
        else
            print_info "No queue or progress files found to clear"
        fi
    else
        print_info "Operation cancelled"
    fi
}

# Function to display help
show_help() {
    echo "Docker Build Requeue Script"
    echo "=========================="
    echo
    echo "This script helps you requeue failed Docker builds from existing build logs."
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  --create, -c     Create a new queue from failed build logs"
    echo "  --status, -s     Show current queue and progress status"
    echo "  --clear          Clear current queue and progress files"
    echo "  --help, -h       Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --create      # Create queue from build logs"
    echo "  $0 --status      # Check current queue status"
    echo "  $0               # Same as --create (default action)"
    echo
    echo "After creating a queue, run './build-docker.sh' to process the failed builds."
}

# Main function
main() {
    local action="create"  # Default action
    
    # Parse command line arguments
    case "${1:-}" in
        --create|-c)
            action="create"
            ;;
        --status|-s)
            action="status"
            ;;
        --clear)
            action="clear"
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        "")
            action="create"  # Default if no arguments
            ;;
        *)
            print_error "Unknown option: $1"
            print_info "Use --help for usage information"
            exit 1
            ;;
    esac
    
    print_info "Docker Build Requeue Script"
    print_info "============================"
    echo
    
    case $action in
        create)
            create_requeue
            ;;
        status)
            show_queue_status
            ;;
        clear)
            clear_queue
            ;;
    esac
}

# Run the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
