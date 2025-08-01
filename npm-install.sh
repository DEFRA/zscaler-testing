#!/bin/bash

# Script to run npm install in repositories with package.json
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
ERRORS_FILE="npm_install_errors.txt"
INSTALL_LOG_DIR="npm_install_logs"
INSTALL_TIMEOUT=600  # 10 minutes timeout for each npm install

# Global counters
GLOBAL_INSTALLS_SUCCESSFUL=0
GLOBAL_INSTALLS_FAILED=0

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

# Function to check if Node.js and npm are installed
check_npm() {
    print_info "Checking Node.js and npm availability..."
    
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    local node_version=$(node --version)
    local npm_version=$(npm --version)
    print_success "Node.js $node_version and npm $npm_version are available."
}

# Function to initialize log files
initialize_logs() {
    print_info "Initializing log files..."
    
    # Create install logs directory
    mkdir -p "$INSTALL_LOG_DIR"
    
    # Initialize or clear the errors file
    echo "NPM Install Errors Report - $(date)" > "$ERRORS_FILE"
    echo "=================================================" >> "$ERRORS_FILE"
    echo "" >> "$ERRORS_FILE"
    
    print_success "Log files initialized."
}

# Function to find package.json files in a repository
find_package_json_files() {
    local repo_path=$1
    local package_files=()
    
    # Look for package.json files in the repository (up to 3 levels deep)
    # Exclude node_modules, .git, and other common directories
    while IFS= read -r -d '' package_file; do
        package_files+=("$package_file")
    done < <(find "$repo_path" -maxdepth 3 -type f -name "package.json" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*" -print0 2>/dev/null)
    
    printf '%s\n' "${package_files[@]}"
}

# Function to run npm install
run_npm_install() {
    local repo_name=$1
    local package_json_path=$2
    local repo_path=$3
    
    # Extract directory containing the package.json
    local package_dir=$(dirname "$package_json_path")
    
    print_info "Running npm install in: $package_dir"
    
    # Create log file for this install
    local current_dir=$(pwd)
    local install_log_file="${current_dir}/${INSTALL_LOG_DIR}/${repo_name}_npm_install.log"
    
    # Ensure the install logs directory exists
    mkdir -p "${current_dir}/${INSTALL_LOG_DIR}"
    
    # Change to the directory containing the package.json
    cd "$package_dir" || return 1
    
    # Create log file header
    echo "NPM Install log for $repo_name - $(date)" > "$install_log_file"
    echo "Package.json: $package_json_path" >> "$install_log_file"
    echo "Working directory: $package_dir" >> "$install_log_file"
    echo "=================================================" >> "$install_log_file"
    
    # Attempt to run npm install with live output
    local install_exit_code
    
    print_info "Starting npm install (live output, ${INSTALL_TIMEOUT}s timeout)..."
    echo
    
    # Run npm install with timeout, show live output and save to log
    timeout "$INSTALL_TIMEOUT" npm install 2>&1 | tee -a "$install_log_file"
    install_exit_code=${PIPESTATUS[0]}
    
    # Check if install was terminated due to timeout
    if [ $install_exit_code -eq 124 ]; then
        echo "NPM install timed out after ${INSTALL_TIMEOUT} seconds" | tee -a "$install_log_file"
    fi
    
    # Add exit code to log file
    echo "" >> "$install_log_file"
    echo "Exit code: $install_exit_code" >> "$install_log_file"
    
    # Return to original directory
    cd - &> /dev/null
    
    if [ $install_exit_code -eq 0 ]; then
        echo
        print_success "Successfully completed npm install for $repo_name"
        ((GLOBAL_INSTALLS_SUCCESSFUL++))
        return 0
    else
        echo
        print_error "Failed npm install for $repo_name (Exit code: $install_exit_code)"
        ((GLOBAL_INSTALLS_FAILED++))
        
        # Log the error to the errors file (reference to install log)
        {
            echo "Repository: $repo_name"
            echo "Package.json: $package_json_path"
            echo "Error occurred on: $(date)"
            echo "Exit code: $install_exit_code"
            echo "Detailed install log: $install_log_file"
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
    
    # Find all package.json files in the repository
    local package_files
    package_files=($(find_package_json_files "$repo_path"))
    
    if [ ${#package_files[@]} -eq 0 ]; then
        print_warning "No package.json found in $repo_name"
        return 1
    fi
    
    print_info "Found ${#package_files[@]} package.json file(s) in $repo_name"
    
    local success_count=0
    local error_count=0
    
    # Process each package.json file
    for package_file in "${package_files[@]}"; do
        print_info "Processing package.json: $package_file"
        
        if run_npm_install "$repo_name" "$package_file" "$repo_path"; then
            ((success_count++))
        else
            ((error_count++))
        fi
        
        echo  # Add some spacing
    done
    
    # Report results for this repository
    if [ $success_count -gt 0 ] && [ $error_count -eq 0 ]; then
        print_success "Repository $repo_name: All $success_count npm install(s) successful"
        return 0
    elif [ $success_count -gt 0 ] && [ $error_count -gt 0 ]; then
        print_warning "Repository $repo_name: $success_count successful, $error_count failed"
        return 2  # Mixed results
    else
        print_error "Repository $repo_name: All $error_count npm install(s) failed"
        return 3  # All failed
    fi
}

# Function to display final summary
display_summary() {
    local total_repos=$1
    local repos_with_package_json=$2
    local repos_processed=$3
    local total_installs_attempted=$4
    local total_installs_successful=$5
    local total_installs_failed=$6
    
    echo
    print_info "=== FINAL SUMMARY ==="
    echo "Total repositories checked: $total_repos"
    echo "Repositories with package.json: $repos_with_package_json"
    echo "Repositories processed: $repos_processed"
    echo "Total npm installs attempted: $total_installs_attempted"
    echo "Total successful installs: $total_installs_successful"
    echo "Total failed installs: $total_installs_failed"
    echo
    
    if [ $total_installs_failed -gt 0 ]; then
        print_warning "Install errors have been logged to: $ERRORS_FILE"
    fi
    
    if [ -d "$INSTALL_LOG_DIR" ]; then
        print_info "Detailed install logs are available in: $INSTALL_LOG_DIR/"
    fi
    
    if [ $total_installs_successful -gt 0 ]; then
        print_success "All successful npm installs have completed."
    fi
}

# Main function
main() {
    print_info "Starting npm install process for repositories with package.json..."
    echo
    
    # Check prerequisites
    check_npm
    
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
        # Skip non-repository directories
        if [[ "$repo_name" != "npm_install_logs" && "$repo_name" != "docker_build_logs" && "$repo_name" != "." ]]; then
            repositories+=("$repo_name")
        fi
    done < <(find "$REPOS_DIR" -maxdepth 1 -type d ! -name "$REPOS_DIR" -print0 2>/dev/null)
    
    if [ ${#repositories[@]} -eq 0 ]; then
        print_error "No repositories found in '$REPOS_DIR' directory."
        exit 1
    fi
    
    print_info "Found ${#repositories[@]} repositories to process."
    echo
    
    # Initialize counters
    local total_repos=${#repositories[@]}
    local repos_with_package_json=0
    local repos_processed=0
    local total_installs_attempted=0
    
    # Process each repository
    for repo_name in "${repositories[@]}"; do
        print_info "=== Processing Repository: $repo_name ==="
        
        # Count package.json files in this repo
        local repo_path="${REPOS_DIR}/${repo_name}"
        local package_files
        package_files=($(find_package_json_files "$repo_path"))
        local package_count=${#package_files[@]}
        
        if [ $package_count -gt 0 ]; then
            ((repos_with_package_json++))
            ((total_installs_attempted += package_count))
            
            # Process the repository
            if process_repository "$repo_name"; then
                ((repos_processed++))
            fi
        else
            print_warning "No package.json files found in $repo_name"
        fi
        
        echo
        echo "================================================="
        echo
    done
    
    # Use global counters for final summary
    local total_installs_successful=$GLOBAL_INSTALLS_SUCCESSFUL
    local total_installs_failed=$GLOBAL_INSTALLS_FAILED
    
    # Display final summary
    display_summary "$total_repos" "$repos_with_package_json" "$repos_processed" \
                   "$total_installs_attempted" "$total_installs_successful" "$total_installs_failed"
}

# Run the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
