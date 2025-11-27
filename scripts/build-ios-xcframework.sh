#!/bin/bash

# =============================================================================
# Wasmi iOS XCFramework Build Script
# =============================================================================
# 
# This script builds wasmi_c_api as an XCFramework for iOS, supporting:
#   - iOS devices (aarch64-apple-ios)
#   - iOS ARM simulators (aarch64-apple-ios-sim)
#
# Features enabled: SIMD
#
# Usage: ./scripts/build-ios-xcframework.sh
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/artifacts"
XCFRAMEWORK_NAME="Wasmi"

# Rust targets
IOS_DEVICE_TARGET="aarch64-apple-ios"
IOS_SIM_TARGET="aarch64-apple-ios-sim"

# Build configuration
CARGO_PROFILE="release"
FEATURES="simd"

# Paths
C_API_DIR="${PROJECT_ROOT}/crates/c_api"
ARTIFACT_DIR="${C_API_DIR}/artifact"
INCLUDE_DIR="${C_API_DIR}/include"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Prerequisite Checks
# -----------------------------------------------------------------------------

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    check_command "rustup"
    check_command "cargo"
    check_command "xcodebuild"
    
    log_success "All prerequisites are installed."
}

# -----------------------------------------------------------------------------
# Install Rust Targets
# -----------------------------------------------------------------------------

install_rust_targets() {
    log_info "Installing Rust iOS targets..."
    
    rustup target add "${IOS_DEVICE_TARGET}" "${IOS_SIM_TARGET}"
    
    log_success "Rust targets installed."
}

# -----------------------------------------------------------------------------
# Build Static Libraries
# -----------------------------------------------------------------------------

build_static_lib() {
    local target="$1"
    local target_name="$2"
    
    log_info "Building for ${target_name} (${target})..."
    
    cd "${ARTIFACT_DIR}"
    
    CARGO_PROFILE_RELEASE_PANIC=abort cargo build \
        --target "${target}" \
        --release \
        --features "${FEATURES}"
    
    local lib_path="${PROJECT_ROOT}/target/${target}/${CARGO_PROFILE}/libwasmi.a"
    
    if [[ ! -f "${lib_path}" ]]; then
        log_error "Failed to build library for ${target}"
        exit 1
    fi
    
    log_success "Built ${target_name}: ${lib_path}"
}

build_all_targets() {
    log_info "Building static libraries for all targets..."
    
    build_static_lib "${IOS_DEVICE_TARGET}" "iOS Device"
    build_static_lib "${IOS_SIM_TARGET}" "iOS Simulator (ARM)"
    
    log_success "All static libraries built."
}

# -----------------------------------------------------------------------------
# Prepare Headers
# -----------------------------------------------------------------------------

prepare_headers() {
    local headers_dir="$1"

    log_info "Preparing headers in ${headers_dir}..."

    # Create headers directory
    mkdir -p "${headers_dir}/wasmi"

    # Copy main headers
    cp "${INCLUDE_DIR}/wasm.h" "${headers_dir}/"
    cp "${INCLUDE_DIR}/wasmi.h" "${headers_dir}/"

    # Copy wasmi subdirectory headers
    cp "${INCLUDE_DIR}/wasmi/config.h" "${headers_dir}/wasmi/"
    cp "${INCLUDE_DIR}/wasmi/engine.h" "${headers_dir}/wasmi/"
    cp "${INCLUDE_DIR}/wasmi/error.h" "${headers_dir}/wasmi/"
    cp "${INCLUDE_DIR}/wasmi/store.h" "${headers_dir}/wasmi/"

    # Copy modulemap for Swift compatibility
    if [[ -f "${INCLUDE_DIR}/module.modulemap" ]]; then
        cp "${INCLUDE_DIR}/module.modulemap" "${headers_dir}/"
        log_info "Copied modulemap for Swift compatibility"
    fi

    # Generate conf.h from template
    cat > "${headers_dir}/wasmi/conf.h" << 'EOF'
/**
 * \file wasmi/conf.h
 *
 * \brief Build-time defines for how the C API was built.
 */

#ifndef WASMI_CONF_H
#define WASMI_CONF_H

// Built with SIMD support enabled
#define WASMI_FEATURE_SIMD 1

#endif // WASMI_CONF_H
EOF

    log_success "Headers prepared."
}

# -----------------------------------------------------------------------------
# Create XCFramework
# -----------------------------------------------------------------------------

create_xcframework() {
    log_info "Creating XCFramework..."
    
    # Clean up previous output
    rm -rf "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}.xcframework"
    mkdir -p "${OUTPUT_DIR}"
    
    # Prepare temporary directories for each platform
    local temp_dir="${OUTPUT_DIR}/temp_xcframework"
    rm -rf "${temp_dir}"
    mkdir -p "${temp_dir}"
    
    # Prepare iOS Device
    local ios_device_dir="${temp_dir}/ios-device"
    mkdir -p "${ios_device_dir}"
    cp "${PROJECT_ROOT}/target/${IOS_DEVICE_TARGET}/${CARGO_PROFILE}/libwasmi.a" "${ios_device_dir}/"
    prepare_headers "${ios_device_dir}/Headers"
    
    # Prepare iOS Simulator
    local ios_sim_dir="${temp_dir}/ios-simulator"
    mkdir -p "${ios_sim_dir}"
    cp "${PROJECT_ROOT}/target/${IOS_SIM_TARGET}/${CARGO_PROFILE}/libwasmi.a" "${ios_sim_dir}/"
    prepare_headers "${ios_sim_dir}/Headers"
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -library "${ios_device_dir}/libwasmi.a" \
        -headers "${ios_device_dir}/Headers" \
        -library "${ios_sim_dir}/libwasmi.a" \
        -headers "${ios_sim_dir}/Headers" \
        -output "${OUTPUT_DIR}/${XCFRAMEWORK_NAME}.xcframework"
    
    # Clean up temp directory
    rm -rf "${temp_dir}"
    
    log_success "XCFramework created at: ${OUTPUT_DIR}/${XCFRAMEWORK_NAME}.xcframework"
}

# -----------------------------------------------------------------------------
# Print Summary
# -----------------------------------------------------------------------------

print_summary() {
    echo ""
    echo "============================================================================="
    echo -e "${GREEN}Build Complete!${NC}"
    echo "============================================================================="
    echo ""
    echo "XCFramework location:"
    echo "  ${OUTPUT_DIR}/${XCFRAMEWORK_NAME}.xcframework"
    echo ""
    echo "Supported platforms:"
    echo "  - iOS devices (arm64)"
    echo "  - iOS Simulator (arm64)"
    echo ""
    echo "Features enabled:"
    echo "  - SIMD"
    echo ""
    echo "To use in Xcode:"
    echo "  1. Drag the .xcframework into your Xcode project"
    echo "  2. Add to 'Frameworks, Libraries, and Embedded Content'"
    echo "  3. For Objective-C: #include <wasm.h> or #include <wasmi.h>"
    echo "  4. For Swift: import Wasmi"
    echo ""
    echo "============================================================================="
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo ""
    echo "============================================================================="
    echo "Wasmi iOS XCFramework Builder"
    echo "============================================================================="
    echo ""
    
    cd "${PROJECT_ROOT}"
    
    check_prerequisites
    install_rust_targets
    build_all_targets
    create_xcframework
    print_summary
}

main "$@"



