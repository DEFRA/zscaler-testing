#!/bin/bash

# Script to clone all repositories from DEFRA GitHub organization
# Author: Auto-generated script
# Date: $(date)

# Note: We don't use 'set -e' because we expect some clone operations might fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_ORG="DEFRA"
REPOS_DIR="repos"
GITHUB_API_URL="https://api.github.com/orgs/${GITHUB_ORG}/repos"

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

# Function to check if required tools are installed
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed. Please install curl."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq is required but not installed. Please install jq."
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        print_error "git is required but not installed. Please install git."
        exit 1
    fi
    
    print_success "All prerequisites are installed."
}

# Function to create repos directory
create_repos_directory() {
    if [ ! -d "$REPOS_DIR" ]; then
        print_info "Creating repos directory..."
        mkdir -p "$REPOS_DIR"
        print_success "Created $REPOS_DIR directory."
    else
        print_info "Using existing $REPOS_DIR directory."
    fi
}

# Function to fetch all GitHub repositories from DEFRA organization
fetch_github_repos() {
    local page=1
    local per_page=100
    local all_repos=()
    
    print_info "Fetching repositories from GitHub organization: $GITHUB_ORG"
    
    while true; do
        local url="${GITHUB_API_URL}?page=${page}&per_page=${per_page}&type=all"
        
        print_info "Fetching page $page..."
        local response=$(curl -s "$url" 2>/dev/null)
        if [ $? -ne 0 ]; then
            print_error "Failed to fetch page $page from GitHub API"
            break
        fi
        
        # Check if response is an error
        local error_message=$(echo "$response" | jq -r '.message // empty' 2>/dev/null)
        if [ -n "$error_message" ]; then
            print_error "GitHub API error: $error_message"
            break
        fi
        
        local repos=$(echo "$response" | jq -r '.[].name' 2>/dev/null)
        
        if [ -z "$repos" ] || [ "$repos" = "null" ]; then
            break
        fi
        
        local repo_count=0
        while IFS= read -r repo; do
            if [ -n "$repo" ] && [ "$repo" != "null" ]; then
                all_repos+=("$repo")
                ((repo_count++))
            fi
        done <<< "$repos"
        
        print_info "Found $repo_count repositories on page $page"
        
        # If we got fewer repositories than per_page, we're on the last page
        if [ $repo_count -lt $per_page ]; then
            break
        fi
        
        ((page++))
    done
    
    # Output only the repository names, one per line
    printf '%s\n' "${all_repos[@]}"
}

# Function to clone a repository
clone_repository() {
    local repo_name=$1
    local github_url="https://github.com/${GITHUB_ORG}/${repo_name}.git"
    local target_dir="${REPOS_DIR}/${repo_name}"
    
    if [ -d "$target_dir" ]; then
        print_warning "Repository $repo_name already exists in $target_dir. Skipping..."
        return 2  # Return 2 for "already exists"
    fi
    
    print_info "Cloning repository: $repo_name"
    if git clone "$github_url" "$target_dir" 2>/dev/null; then
        print_success "Successfully cloned $repo_name"
        return 0  # Return 0 for success
    else
        print_error "Failed to clone $repo_name"
        return 3  # Return 3 for "clone failed"
    fi
}

# Function to display summary
display_summary() {
    local total=$1
    local successful=$2
    local failed=$3
    local skipped=$4
    
    echo
    print_info "=== SUMMARY ==="
    echo "Total repositories found in GitHub organization: $total"
    echo "Successfully cloned: $successful"
    echo "Skipped (already exists): $skipped"
    echo "Failed to clone: $failed"
    echo
    
    if [ $successful -gt 0 ]; then
        print_success "Cloned repositories are available in the '$REPOS_DIR' directory."
    fi
    
    if [ $failed -gt 0 ]; then
        print_warning "Some repositories failed to clone. Check the output above for details."
    fi
}

# Main function
main() {
    print_info "Starting repository cloning process..."
    print_info "GitHub Organization: $GITHUB_ORG"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Create repos directory
    create_repos_directory
    
    # Fetch GitHub repositories
    print_info "Fetching all repositories from GitHub organization: $GITHUB_ORG"
    local github_repos_output
    github_repos_output=$(fetch_github_repos)
    
    if [ $? -ne 0 ] || [ -z "$github_repos_output" ]; then
        print_error "Failed to fetch repositories from GitHub organization: $GITHUB_ORG"
        exit 1
    fi
    
    # Convert output to array
    local github_repos=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            github_repos+=("$line")
        fi
    done <<< "$github_repos_output"
    
    if [ ${#github_repos[@]} -eq 0 ]; then
        print_error "No repositories found in GitHub organization: $GITHUB_ORG"
        exit 1
    fi
    
    print_success "Found ${#github_repos[@]} repositories in GitHub organization."
    
    # Clone repositories
    local total=${#github_repos[@]}
    local successful=0
    local failed=0
    local skipped=0
    
    print_info "Starting to clone $total repositories..."
    echo
    
    for repo in "${github_repos[@]}"; do
        print_info "Processing repository: $repo"
        
        clone_repository "$repo"
        result=$?
        
        case $result in
            0)
                ((successful++))
                ;;
            2)
                ((skipped++))  # Repository already exists locally
                ;;
            3)
                ((failed++))  # Clone operation failed
                ;;
        esac
        echo
    done
    
    # Display summary
    display_summary "$total" "$successful" "$failed" "$skipped"
}

# Run the script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
