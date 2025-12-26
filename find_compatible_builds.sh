#!/bin/bash
set -e

CUSTOM_NODES_DIR="${1:-custom_nodes}"
REPOS_FILE="${2:-custom_node_repos.txt}"
OUTPUT_DIR="build_configs"
MAX_RELEASES=3
MAX_COMMITS=5

# Auto-detect ComfyUI directory
find_comfyui_dir() {
    if [ -f "requirements.txt" ] && [ -f "main.py" ]; then
        echo "."
        return
    fi
    
    if [ -f "../requirements.txt" ] && [ -f "../main.py" ]; then
        echo ".."
        return
    fi
    
    if [ -d "ComfyUI" ] && [ -f "ComfyUI/requirements.txt" ]; then
        echo "ComfyUI"
        return
    fi
    
    if [ -d "../ComfyUI" ] && [ -f "../ComfyUI/requirements.txt" ]; then
        echo "../ComfyUI"
        return
    fi
    
    echo ""
}

COMFYUI_DIR=$(find_comfyui_dir)

if [ -z "$COMFYUI_DIR" ]; then
    echo "Error: Cannot find ComfyUI directory"
    exit 1
fi

MANAGER_DIR="${COMFYUI_DIR}/custom_nodes/ComfyUI-Manager"

mkdir -p "$OUTPUT_DIR" /tmp/compat_analysis

echo "=== Dynamic Compatibility Analysis ==="
echo "Set 0 (Anchors): ComfyUI + ComfyUI-Manager (latest)"
echo ""

# Extract anchor requirements
extract_anchor_requirements() {
    local anchor_file="/tmp/compat_analysis/anchors.txt"
    > "$anchor_file"
    
    echo "=== Set 0: Anchor Requirements ==="
    
    if [ -f "${COMFYUI_DIR}/requirements.txt" ]; then
        echo "ComfyUI:"
        while IFS= read -r req; do
            clean_req=$(echo "$req" | sed 's/#.*//' | sed 's/[[:space:]]*$//')
            [ -z "$clean_req" ] && continue
            [[ "$clean_req" =~ ^#.*$ ]] && continue
            
            pkg_name=$(echo "$clean_req" | sed -E 's/([a-zA-Z0-9_-]+).*/\1/')
            echo "  $clean_req"
            echo "${pkg_name}|${clean_req}|ComfyUI|ANCHOR" >> "$anchor_file"
        done < "${COMFYUI_DIR}/requirements.txt"
    fi
    
    echo ""
    
    if [ -f "${MANAGER_DIR}/requirements.txt" ]; then
        echo "ComfyUI-Manager:"
        while IFS= read -r req; do
            clean_req=$(echo "$req" | sed 's/#.*//' | sed 's/[[:space:]]*$//')
            [ -z "$clean_req" ] && continue
            [[ "$clean_req" =~ ^#.*$ ]] && continue
            
            pkg_name=$(echo "$clean_req" | sed -E 's/([a-zA-Z0-9_-]+).*/\1/')
            echo "  $clean_req"
            echo "${pkg_name}|${clean_req}|ComfyUI-Manager|ANCHOR" >> "$anchor_file"
        done < "${MANAGER_DIR}/requirements.txt"
    fi
    
    echo ""
}

# Extract node requirements
extract_current_requirements() {
    local repos_file="$1"
    local output_file="/tmp/compat_analysis/current_deps.txt"
    
    if [ -f /tmp/compat_analysis/anchors.txt ]; then
        cat /tmp/compat_analysis/anchors.txt > "$output_file"
    else
        > "$output_file"
    fi
    
    while IFS= read -r repo || [ -n "$repo" ]; do
        [ -z "$repo" ] && continue
        [[ "$repo" =~ ^#.*$ ]] && continue
        
        node_name=$(basename "$repo")
        node_dir="${CUSTOM_NODES_DIR}/${node_name}"
        
        if [ -f "${node_dir}/requirements.txt" ]; then
            while IFS= read -r req; do
                clean_req=$(echo "$req" | sed 's/#.*//' | sed 's/[[:space:]]*$//')
                [ -z "$clean_req" ] && continue
                [[ "$clean_req" =~ ^#.*$ ]] && continue
                
                pkg_name=$(echo "$clean_req" | sed -E 's/([a-zA-Z0-9_-]+).*/\1/')
                echo "${pkg_name}|${clean_req}|${node_name}|HEAD" >> "$output_file"
            done < "${node_dir}/requirements.txt"
        fi
    done < "$repos_file"
}

# Version comparison
version_conflicts() {
    local anchor_req="$1"
    local node_req="$2"
    
    local anchor_op=$(echo "$anchor_req" | sed -E 's/^[^><=!]+([><=!]+).*/\1/')
    local anchor_ver=$(echo "$anchor_req" | sed -E 's/^[^0-9]*([0-9.]+).*/\1/')
    local node_op=$(echo "$node_req" | sed -E 's/^[^><=!]+([><=!]+).*/\1/')
    local node_ver=$(echo "$node_req" | sed -E 's/^[^0-9]*([0-9.]+).*/\1/')
    
    if [ -z "$anchor_ver" ] || [ -z "$node_ver" ]; then
        return 1
    fi
    
    version_compare() {
        local v1="$1"
        local op="$2"
        local v2="$3"
        
        v1_num=$(echo "$v1" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
        v2_num=$(echo "$v2" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
        
        case "$op" in
            "==") [ "$v1_num" -eq "$v2_num" ] && return 0 || return 1 ;;
            ">=") [ "$v1_num" -ge "$v2_num" ] && return 0 || return 1 ;;
            "<=") [ "$v1_num" -le "$v2_num" ] && return 0 || return 1 ;;
            ">")  [ "$v1_num" -gt "$v2_num" ] && return 0 || return 1 ;;
            "<")  [ "$v1_num" -lt "$v2_num" ] && return 0 || return 1 ;;
        esac
        return 1
    }
    
    if [[ "$anchor_op" == "==" ]] && [[ "$node_op" == "==" ]]; then
        if ! version_compare "$anchor_ver" "==" "$node_ver"; then
            return 0
        fi
    fi
    
    if [[ "$anchor_op" == ">=" ]] && [[ "$node_op" == "==" ]]; then
        if ! version_compare "$node_ver" ">=" "$anchor_ver"; then
            return 0
        fi
    fi
    
    if [[ "$anchor_op" == ">=" ]] && [[ "$node_op" =~ ^\< ]]; then
        if version_compare "$anchor_ver" ">=" "$node_ver"; then
            return 0
        fi
    fi
    
    if [[ "$anchor_op" == ">=" ]] && [[ "$node_op" == "<=" ]]; then
        if version_compare "$anchor_ver" ">" "$node_ver"; then
            return 0
        fi
    fi
    
    return 1
}

conflicts_with_anchor() {
    local pkg="$1"
    local requirement="$2"
    local anchor_file="/tmp/compat_analysis/anchors.txt"
    
    anchor_req=$(grep "^${pkg}|" "$anchor_file" 2>/dev/null | head -1 | cut -d'|' -f2)
    
    if [ -z "$anchor_req" ]; then
        echo "NO_ANCHOR"
        return
    fi
    
    if version_conflicts "$anchor_req" "$requirement"; then
        echo "CONFLICT"
        return
    fi
    
    echo "COMPATIBLE"
}

# Check if Manager is compatible with target ComfyUI version
check_manager_compatibility() {
    local comfyui_version="$1"
    
    if [ ! -d "$MANAGER_DIR" ]; then
        echo "NOT_FOUND"
        return
    fi
    
    cd "$MANAGER_DIR"
    
    if [ ! -f "requirements.txt" ]; then
        echo "COMPATIBLE"
        cd - > /dev/null
        return
    fi
    
    local manager_tf_req=$(grep "^transformers" requirements.txt | head -1)
    
    if [ -z "$manager_tf_req" ]; then
        echo "COMPATIBLE"
        cd - > /dev/null
        return
    fi
    
    cd "$COMFYUI_DIR"
    local comfyui_tf_req=$(git show ${comfyui_version}:requirements.txt 2>/dev/null | grep "^transformers" | head -1)
    
    if [ -z "$comfyui_tf_req" ]; then
        echo "COMPATIBLE"
        cd - > /dev/null
        return
    fi
    
    if version_conflicts "$comfyui_tf_req" "$manager_tf_req"; then
        echo "INCOMPATIBLE"
    else
        echo "COMPATIBLE"
    fi
    
    cd - > /dev/null
}

# Find compatible ComfyUI release for set-off nodes
# Find compatible ComfyUI release for set-off nodes
find_compatible_comfyui_release() {
    echo ""
    echo "=== Finding Compatible ComfyUI Release for Set-Off Nodes ==="
    
    cd "$COMFYUI_DIR"
    
    local releases=$(git tag --sort=-version:refname | grep -E '^v[0-9]' | head -n $MAX_RELEASES)
    
    if [ -z "$releases" ]; then
        echo "No releases found, checking last $MAX_COMMITS commits..."
        releases=$(git log --oneline -n $MAX_COMMITS --format="%H")
    fi
    
    for ref in $releases; do
        echo "Checking ComfyUI: $ref"
        
        local req_content=$(git show ${ref}:requirements.txt 2>/dev/null)
        
        if [ -z "$req_content" ]; then
            continue
        fi
        
        local tf_req=$(echo "$req_content" | grep "^transformers" | head -1)
        
        if [ -z "$tf_req" ]; then
            continue
        fi
        
        echo "  transformers: $tf_req"
        
        if [[ "$tf_req" =~ transformers\>\=([0-9.]+) ]]; then
            local min_ver="${BASH_REMATCH[1]}"
            local min_num=$(echo "$min_ver" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
            local target_num=$(echo "4.39.3" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
            
            if [ "$min_num" -le "$target_num" ]; then
                echo "  ✓ Compatible with set-off nodes!"
                
                local manager_compat=$(check_manager_compatibility "$ref")
                
                if [ "$manager_compat" = "COMPATIBLE" ]; then
                    echo "  ✓ ComfyUI-Manager is compatible"
                    echo "$ref|WITH_MANAGER" > "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt"
                elif [ "$manager_compat" = "NOT_FOUND" ]; then
                    echo "  ⚠ ComfyUI-Manager not found"
                    echo "$ref|WITHOUT_MANAGER" > "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt"
                else
                    echo "  ✗ ComfyUI-Manager conflicts - will be excluded"
                    echo "$ref|WITHOUT_MANAGER" > "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt"
                fi
                
                cd - > /dev/null
                return 0
            fi
        fi
    done
    
    cd - > /dev/null
    echo "  ✗ No compatible version found in last $MAX_RELEASES releases"
    echo "  → Will use unified build with package override"
    echo "NONE|OVERRIDE" > "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt"
    return 1
}

# Categorize nodes
categorize_nodes() {
    local deps_file="$1"
    local repos_file="$2"
    
    local base_file="$OUTPUT_DIR/set-base.txt"
    local off_file="$OUTPUT_DIR/set-off.txt"
    local unified_file="$OUTPUT_DIR/set-unified.txt"
    
    > "$base_file"
    > "$off_file"
    > "$unified_file"
    
    echo "# Set-Base: Compatible with latest ComfyUI + Manager" > "$base_file"
    echo "# Set-Off: Incompatible with latest ComfyUI (needs older version)" > "$off_file"
    echo "# Set-Unified: All nodes (set-off will use overridden packages)" > "$unified_file"
    
    echo "=== Categorizing Nodes ==="
    echo ""
    
    while IFS= read -r repo || [ -n "$repo" ]; do
        [ -z "$repo" ] && continue
        [[ "$repo" =~ ^#.*$ ]] && continue
        
        node_name=$(basename "$repo")
        node_dir="${CUSTOM_NODES_DIR}/${node_name}"
        
        if [ ! -d "$node_dir" ]; then
            continue
        fi
        
        has_conflict=0
        conflict_packages=""
        
        if [ -f "${node_dir}/requirements.txt" ]; then
            while IFS= read -r req; do
                clean_req=$(echo "$req" | sed 's/#.*//' | sed 's/[[:space:]]*$//')
                [ -z "$clean_req" ] && continue
                [[ "$clean_req" =~ ^#.*$ ]] && continue
                
                pkg_name=$(echo "$clean_req" | sed -E 's/([a-zA-Z0-9_-]+).*/\1/')
                conflict_status=$(conflicts_with_anchor "$pkg_name" "$clean_req")
                
                if [ "$conflict_status" = "CONFLICT" ]; then
                    has_conflict=1
                    conflict_packages="$conflict_packages $pkg_name($clean_req)"
                fi
            done < "${node_dir}/requirements.txt"
        fi
        
        echo "$repo" >> "$unified_file"
        
        if [ $has_conflict -eq 1 ]; then
            echo "✗ Set-Off: $node_name"
            echo "  Conflicts:$conflict_packages"
            echo "$repo  #$conflict_packages" >> "$off_file"
        else
            echo "✓ Set-Base: $node_name"
            echo "$repo" >> "$base_file"
        fi
    done < "$repos_file"
}

# Generate report
# Generate report
generate_report() {
    local base_count=$(grep -v "^#" "$OUTPUT_DIR/set-base.txt" 2>/dev/null | grep -v "^$" | wc -l)
    local off_count=$(grep -v "^#" "$OUTPUT_DIR/set-off.txt" 2>/dev/null | grep -v "^$" | wc -l)
    local unified_count=$(grep -v "^#" "$OUTPUT_DIR/set-unified.txt" 2>/dev/null | grep -v "^$" | wc -l)
    local compat_version=""
    local manager_status=""
    
    if [ -f "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt" ]; then
        local compat_line=$(cat "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt")
        compat_version=$(echo "$compat_line" | cut -d'|' -f1)
        manager_status=$(echo "$compat_line" | cut -d'|' -f2)
    fi
    
    cat > "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
=== Node Split Analysis ===
Generated: $(date)

CONFLICTING NODES (${off_count})
---------------------------------
$(grep -v "^#" "$OUTPUT_DIR/set-off.txt" 2>/dev/null | sed 's/  #/ - /')

BUILD OPTIONS
-------------

OPTION 1: Unified Build (Recommended - Single Image)
  File: set-unified.txt
  Nodes: $unified_count (all nodes)
  ComfyUI: latest
  Manager: latest
  Strategy: Latest ComfyUI packages override conflicting node requirements
  ⚠ ${off_count} conflicting nodes will use ComfyUI's package versions
  ⚠ These nodes may not function correctly

REPORT

    if [ "$compat_version" != "NONE" ] && [ -n "$compat_version" ]; then
        cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT

OPTION 2: Split Builds (Maximum Compatibility Available)
  
  Build A: Latest Stack
    File: set-base.txt
    Nodes: $base_count
    ComfyUI: latest
    Manager: latest
  
  Build B: Legacy Stack (for conflicting nodes)
    File: set-off.txt
    Nodes: $off_count
    ComfyUI: $compat_version
REPORT
        
        if [ "$manager_status" = "WITH_MANAGER" ]; then
            cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
    Manager: latest (compatible)
REPORT
        else
            cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
    Manager: ✗ EXCLUDED (conflicts with ComfyUI $compat_version)
REPORT
        fi
    else
        cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT

OPTION 2: Split Builds (Not Available)
  ✗ No compatible ComfyUI version found for set-off nodes
  Only Option 1 (Unified) or Option 3 (Exclude) are viable
REPORT
    fi
    
    cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT

OPTION 3: Latest Only (Exclude Incompatible Nodes)
  File: set-base.txt
  Nodes: $base_count
  ComfyUI: latest
  Manager: latest
  Strategy: Exclude ${off_count} problematic nodes entirely

RECOMMENDATION
--------------
REPORT

    if [ "$compat_version" != "NONE" ] && [ -n "$compat_version" ] && [ "$off_count" -le 3 ]; then
        cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
Use Option 2 (Split Builds) for maximum compatibility.
Conflicting nodes are few - worth maintaining separate image.
REPORT
    elif [ "$compat_version" = "NONE" ] || [ -z "$compat_version" ]; then
        cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
Use Option 1 (Unified Build) - no compatible ComfyUI version exists.
Test if ${off_count} conflicting nodes work with package overrides.
If critical functionality breaks, use Option 3 to exclude them.
REPORT
    elif [ "$off_count" -le 2 ]; then
        cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
Use Option 3 (Exclude ${off_count} nodes) - not worth separate build.
REPORT
    else
        cat >> "$OUTPUT_DIR/SPLIT_REPORT.txt" <<REPORT
Use Option 1 (Unified) and test if conflicting nodes work.
If critical nodes break, fall back to Option 2 (Split Builds).
REPORT
    fi
    
    # Save recommended option
    if [ "$compat_version" != "NONE" ] && [ -n "$compat_version" ] && [ "$off_count" -le 3 ]; then
        echo "OPTION_2" > "$OUTPUT_DIR/BUILD_STRATEGY.txt"
    else
        echo "OPTION_1" > "$OUTPUT_DIR/BUILD_STRATEGY.txt"
    fi
    
    cat "$OUTPUT_DIR/SPLIT_REPORT.txt"
}

# Main
main() {
    if [ ! -f "$REPOS_FILE" ]; then
        echo "Error: $REPOS_FILE not found"
        exit 1
    fi
    
    extract_anchor_requirements
    extract_current_requirements "$REPOS_FILE"
    categorize_nodes "/tmp/compat_analysis/current_deps.txt" "$REPOS_FILE"
    
    local off_count=$(grep -v "^#" "$OUTPUT_DIR/set-off.txt" 2>/dev/null | grep -v "^$" | wc -l)
    if [ "$off_count" -gt 0 ]; then
        find_compatible_comfyui_release
    fi
    
    echo ""
    generate_report
    echo ""
    echo "=== Analysis Complete ==="
    echo "Files created:"
    echo "  - $OUTPUT_DIR/set-base.txt (compatible nodes)"
    echo "  - $OUTPUT_DIR/set-off.txt (conflicting nodes)"
    echo "  - $OUTPUT_DIR/set-unified.txt (all nodes, overrides conflicts)"
    echo "  - $OUTPUT_DIR/SPLIT_REPORT.txt (build options)"
    if [ -f "$OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt" ]; then
        echo "  - $OUTPUT_DIR/COMPATIBLE_COMFYUI_VERSION.txt (older ComfyUI version)"
    fi
}

main "$@"