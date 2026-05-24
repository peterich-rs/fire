set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

# Print the iOS release coordinates used by archive/TestFlight builds.
ios-release-info version build="" sha="":
    #!/usr/bin/env bash
    set -euo pipefail
    version='{{ version }}'
    build='{{ build }}'
    sha='{{ sha }}'

    if [[ -z "$build" ]]; then
      build="$(git rev-list --count HEAD)"
    fi
    if [[ -z "$sha" ]]; then
      sha="$(git rev-parse HEAD)"
    fi

    short_sha="${sha:0:8}"
    tag="ios-v${version}-b${build}"

    printf 'FIRE_MARKETING_VERSION=%s\n' "$version"
    printf 'FIRE_BUILD_NUMBER=%s\n' "$build"
    printf 'FIRE_GIT_SHA=%s\n' "$sha"
    printf 'short_git_sha=%s\n' "$short_sha"
    printf 'release_tag=%s\n' "$tag"

# Create an annotated iOS release tag for the current commit.
ios-release-tag version build sha="":
    #!/usr/bin/env bash
    set -euo pipefail
    version='{{ version }}'
    build='{{ build }}'
    sha='{{ sha }}'

    if [[ -z "$sha" ]]; then
      sha="$(git rev-parse HEAD)"
    fi

    tag="ios-v${version}-b${build}"
    if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
      echo "tag already exists: ${tag}" >&2
      exit 1
    fi

    git tag -a "$tag" "$sha" -m "iOS ${version} (${build})"
    printf '%s\n' "$tag"

# Push an existing iOS release tag.
ios-release-tag-push version build:
    #!/usr/bin/env bash
    set -euo pipefail
    tag="ios-v{{ version }}-b{{ build }}"

    git rev-parse -q --verify "refs/tags/${tag}" >/dev/null
    git push origin "refs/tags/${tag}"

# Trigger the signed TestFlight workflow without uploading to TestFlight.
ios-testflight-dry-run version build="" ref="":
    #!/usr/bin/env bash
    set -euo pipefail
    version='{{ version }}'
    build='{{ build }}'
    ref='{{ ref }}'

    if [[ -z "$ref" ]]; then
      ref="$(git branch --show-current)"
    fi
    if ! command -v gh >/dev/null 2>&1; then
      echo "gh is required to trigger GitHub Actions workflows" >&2
      exit 1
    fi

    gh workflow run ios-testflight.yml \
      --ref "$ref" \
      -f marketing_version="$version" \
      -f build_number="$build" \
      -f upload_to_testflight=false \
      -f internal_testing_only=true

# Trigger the signed TestFlight workflow and upload to TestFlight.
ios-testflight-upload version build="" ref="" internal_only="true":
    #!/usr/bin/env bash
    set -euo pipefail
    version='{{ version }}'
    build='{{ build }}'
    ref='{{ ref }}'
    internal_only='{{ internal_only }}'

    if [[ -z "$ref" ]]; then
      ref="$(git branch --show-current)"
    fi
    if ! command -v gh >/dev/null 2>&1; then
      echo "gh is required to trigger GitHub Actions workflows" >&2
      exit 1
    fi

    gh workflow run ios-testflight.yml \
      --ref "$ref" \
      -f marketing_version="$version" \
      -f build_number="$build" \
      -f upload_to_testflight=true \
      -f internal_testing_only="$internal_only"
