#!/bin/bash

# Script to clone repositories from DEFRA GitHub based on defradigital Docker Hub repositories
# Author: Auto-generated script
# Date: $(date)

# Note: We don't use 'set -e' because we expect some repositories to not exist on GitHub

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOCKER_HUB_ORG="defradigital"
GITHUB_ORG="DEFRA"
REPOS_DIR="repos"
DOCKER_HUB_API_URL="https://hub.docker.com/v2/repositories/${DOCKER_HUB_ORG}"

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

# Function to fetch Docker Hub repositories
fetch_docker_hub_repos() {
    local page=1
    local per_page=100
    local all_repos=()
    
    while true; do
        local url="${DOCKER_HUB_API_URL}?page=${page}&page_size=${per_page}"
        
        local response=$(curl -s "$url" 2>/dev/null)
        if [ $? -ne 0 ]; then
            break
        fi
        
        local repos=$(echo "$response" | jq -r '.results[].name' 2>/dev/null)
        
        if [ -z "$repos" ] || [ "$repos" = "null" ]; then
            break
        fi
        
        while IFS= read -r repo; do
            if [ -n "$repo" ] && [ "$repo" != "null" ]; then
                all_repos+=("$repo")
            fi
        done <<< "$repos"
        
        # Check if there are more pages
        local next=$(echo "$response" | jq -r '.next' 2>/dev/null)
        if [ "$next" = "null" ] || [ -z "$next" ]; then
            break
        fi
        
        ((page++))
    done
    
    # Output only the repository names, one per line
    printf '%s\n' "${all_repos[@]}"
}

# Function to check if GitHub repository exists
github_repo_exists() {
    local repo_name=$1
    local github_url="https://github.com/${GITHUB_ORG}/${repo_name}"
    
    # Use curl with timeout and only check headers
    if curl -s --max-time 10 --head "$github_url" | head -n 1 | grep -q "200"; then
        return 0
    else
        return 1
    fi
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
    
    print_info "Checking if GitHub repository exists: $repo_name"
    if ! github_repo_exists "$repo_name"; then
        print_warning "GitHub repository $repo_name does not exist in $GITHUB_ORG organization. Skipping..."
        return 1  # Return 1 for "not found"
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
    echo "Total repositories found in Docker Hub: $total"
    echo "Successfully cloned: $successful"
    echo "Skipped (not found on GitHub or already exists): $skipped"
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
    print_info "Docker Hub Organization: $DOCKER_HUB_ORG"
    print_info "GitHub Organization: $GITHUB_ORG"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Create repos directory
    create_repos_directory
    
    # Fetch Docker Hub repositories
    print_info "Fetching repositories from Docker Hub organization: $DOCKER_HUB_ORG"
    local docker_repos_output
    docker_repos_output=$(fetch_docker_hub_repos)
    
    if [ $? -ne 0 ] || [ -z "$docker_repos_output" ]; then
        print_error "Failed to fetch repositories from Docker Hub organization: $DOCKER_HUB_ORG"
        exit 1
    fi
    
    # Convert output to array
    local docker_repos=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            docker_repos+=("$line")
        fi
    done <<< "$docker_repos_output"
    
    if [ ${#docker_repos[@]} -eq 0 ]; then
        print_error "No repositories found in Docker Hub organization: $DOCKER_HUB_ORG"
        exit 1
    fi
    
    print_success "Found ${#docker_repos[@]} repositories in Docker Hub organization."
    
    # Clone repositories
    local total=${#docker_repos[@]}
    local successful=0
    local failed=0
    local skipped=0
    
    print_info "Starting to clone $total repositories..."
    echo
    
    for repo in "${docker_repos[@]}"; do
        print_info "Processing repository: $repo"
        
        clone_repository "$repo"
        result=$?
        
        case $result in
            0)
                ((successful++))
                ;;
            1)
                ((skipped++))  # Repository not found on GitHub
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
