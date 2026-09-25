#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

temp_files=()
cleanup() {
  if [[ ${#temp_files[@]} -gt 0 ]]; then
    rm -f "${temp_files[@]}"
  fi
}
trap cleanup EXIT

echo "# Third-Party Licenses"
echo
echo "Generated on: $(date -u +%Y-%m-%d)"
echo
echo "This inventory is generated from dependency declarations and lockfiles. It is a release-review input, not legal advice."
echo

echo "## Rust Workspace"
echo
if command -v cargo >/dev/null 2>&1; then
  metadata_file="$(mktemp "${TMPDIR:-/tmp}/fire-cargo-metadata.XXXXXX.json")"
  temp_files+=("$metadata_file")
  cargo metadata --manifest-path Cargo.toml --format-version 1 --locked > "$metadata_file"
  python3 - "$metadata_file" "$ROOT_DIR" <<'PY'
import json
import os
import sys
from pathlib import Path

metadata_path = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()
data = json.loads(metadata_path.read_text(encoding="utf-8"))

resolved_ids = {node["id"] for node in data.get("resolve", {}).get("nodes", [])}
workspace_ids = set(data.get("workspace_members", []))

packages = [
    package
    for package in data.get("packages", [])
    if not resolved_ids or package.get("id") in resolved_ids
]


def source_label(package):
    source = package.get("source")
    if package.get("id") in workspace_ids:
        return "workspace"
    if source is None:
        manifest = Path(package.get("manifest_path", ""))
        try:
            return str(manifest.resolve().parent.relative_to(root))
        except (OSError, ValueError):
            return "path"
    if source == "registry+https://github.com/rust-lang/crates.io-index":
        return "crates.io"
    return source


def license_label(package):
    license_value = package.get("license")
    if license_value:
        return license_value
    license_file = package.get("license_file")
    if license_file:
        try:
            return f"license file: {Path(license_file).resolve().relative_to(root)}"
        except (OSError, ValueError):
            return f"license file: {license_file}"
    return "UNKNOWN"


print("| Crate | Version | License | Source |")
print("| --- | --- | --- | --- |")
for package in sorted(packages, key=lambda item: (item.get("name", ""), item.get("version", ""), source_label(item))):
    print(
        f"| {package.get('name', 'unknown')} "
        f"| {package.get('version', '')} "
        f"| {license_label(package)} "
        f"| {source_label(package)} |"
    )
PY
else
  echo "cargo is not installed; falling back to crate names declared in Cargo.lock without license fields."
  echo
  awk '
    /^name = / { name=$3; gsub(/"/, "", name) }
    /^version = / && name != "" { version=$3; gsub(/"/, "", version); print "- " name " " version; name="" }
  ' Cargo.lock | sort -u
fi

echo
echo "## iOS Swift Packages"
echo
ios_package_file="apps/ios-app/Fire.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [[ -f "$ios_package_file" ]]; then
  python3 - "$ios_package_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)

pins = data.get("pins") or data.get("object", {}).get("pins", [])
for pin in sorted(pins, key=lambda item: item.get("identity", item.get("package", ""))):
    identity = pin.get("identity") or pin.get("package") or "unknown"
    location = pin.get("location") or pin.get("repositoryURL") or ""
    state = pin.get("state", {})
    version = state.get("version") or state.get("revision") or ""
    suffix = f" ({version})" if version else ""
    print(f"- {identity}{suffix}: {location}")
PY
else
  echo "No Swift Package.resolved file found at $ios_package_file."
fi

echo
echo "## iOS Vendored Local Packages"
echo
if [[ -f apps/ios-app/LocalPackages/TextureCore/LICENSE-Texture-3.2.0.txt ]]; then
  echo "- Texture 3.2.0: apps/ios-app/LocalPackages/TextureCore/LICENSE-Texture-3.2.0.txt"
else
  echo "No vendored iOS license files found."
fi

echo
echo "## Android Gradle Release Runtime Dependencies"
echo
android_dir="apps/android-app"
android_gradlew="$android_dir/gradlew"
if [[ -x "$android_gradlew" ]]; then
  android_deps_file="$(mktemp "${TMPDIR:-/tmp}/fire-android-deps.XXXXXX.txt")"
  android_init_file="$(mktemp "${TMPDIR:-/tmp}/fire-android-deps.XXXXXX.gradle")"
  temp_files+=("$android_deps_file" "$android_init_file")
  python3 - "$android_init_file" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    """import org.gradle.api.artifacts.component.ModuleComponentIdentifier
import org.gradle.api.artifacts.result.ResolvedArtifactResult
import org.gradle.maven.MavenModule
import org.gradle.maven.MavenPomArtifact

allprojects {
    tasks.register('firePrintResolvedRuntimeDependencies') {
        doLast {
            def config = configurations.findByName('releaseRuntimeClasspath')
            def identifiers = new LinkedHashSet()
            if (config != null && config.canBeResolved) {
                config.incoming.resolutionResult.allComponents.each { component ->
                    def id = component.id
                    if (id instanceof ModuleComponentIdentifier) {
                        identifiers.add(id)
                    }
                }
            }

            def pomByCoordinate = [:]
            if (!identifiers.isEmpty()) {
                def result = dependencies.createArtifactResolutionQuery()
                    .forComponents(identifiers)
                    .withArtifacts(MavenModule, MavenPomArtifact)
                    .execute()
                result.resolvedComponents.each { component ->
                    def id = component.id
                    if (id instanceof ModuleComponentIdentifier) {
                        def pom = component.getArtifacts(MavenPomArtifact)
                            .find { artifact -> artifact instanceof ResolvedArtifactResult }
                        if (pom != null) {
                            pomByCoordinate["${id.group}:${id.module}:${id.version}"] = pom.file.absolutePath
                        }
                    }
                }
            }

            def lines = new TreeSet()
            identifiers.each { id ->
                def coordinate = "${id.group}:${id.module}:${id.version}"
                lines.add("FIRE_DEP\\t${coordinate}\\t${pomByCoordinate[coordinate] ?: ''}")
            }
            lines.each { println it }
        }
    }
}
""",
    encoding="utf-8",
)
PY
  "$android_gradlew" --quiet --init-script "$android_init_file" -p "$android_dir" firePrintResolvedRuntimeDependencies > "$android_deps_file"
  python3 - "$android_deps_file" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

deps_path = Path(sys.argv[1])
gradle_home = Path(os.environ.get("GRADLE_USER_HOME", str(Path.home() / ".gradle")))
pom_cache = gradle_home / "caches/modules-2/files-2.1"


def child_text(element, name):
    namespace = ""
    if element.tag.startswith("{"):
        namespace = element.tag.split("}", 1)[0] + "}"
    child = element.find(f"./{namespace}{name}")
    if child is None or child.text is None:
        return None
    value = " ".join(child.text.split())
    return value or None


def find_pom(group, module, version):
    module_dir = pom_cache / group / module / version
    matches = sorted(module_dir.glob(f"*/{module}-{version}.pom"))
    return matches[0] if matches else None


def license_entries_from_pom(pom_path, visited=None):
    if visited is None:
        visited = set()
    try:
        resolved_path = pom_path.resolve()
    except OSError:
        resolved_path = pom_path
    if resolved_path in visited:
        return []
    visited.add(resolved_path)

    try:
        root = ET.parse(pom_path).getroot()
    except ET.ParseError:
        return []

    namespace = ""
    if root.tag.startswith("{"):
        namespace = root.tag.split("}", 1)[0] + "}"

    entries = []
    for license_element in root.findall(f"./{namespace}licenses/{namespace}license"):
        name = child_text(license_element, "name")
        url = child_text(license_element, "url")
        if name:
            entries.append((name, url or ""))
    if entries:
        return entries

    parent = root.find(f"./{namespace}parent")
    if parent is None:
        return []
    parent_group = child_text(parent, "groupId")
    parent_module = child_text(parent, "artifactId")
    parent_version = child_text(parent, "version")
    if not parent_group or not parent_module or not parent_version:
        return []
    parent_pom = find_pom(parent_group, parent_module, parent_version)
    if parent_pom is None:
        return []
    return license_entries_from_pom(parent_pom, visited)


def markdown(value):
    return value.replace("|", "\\|")


coordinates = {}
for line in deps_path.read_text(encoding="utf-8").splitlines():
    if line.startswith("FIRE_DEP\t"):
        fields = line.split("\t", 2)
        if len(fields) == 3:
            coordinates[fields[1]] = Path(fields[2]) if fields[2] else None

print("Resolved from Gradle `releaseRuntimeClasspath`; license names are read from Maven POM metadata resolved by Gradle.")
print()
print("| Component | Version | License | License URL |")
print("| --- | --- | --- | --- |")
for coordinate, pom in sorted(coordinates.items()):
    group, module, version = coordinate.split(":", 2)
    entries = license_entries_from_pom(pom) if pom is not None else []
    if entries:
        names = "; ".join(dict.fromkeys(name for name, _ in entries))
        urls = "; ".join(dict.fromkeys(url for _, url in entries if url))
    else:
        names = "UNKNOWN"
        urls = ""
    print(f"| {markdown(group + ':' + module)} | {markdown(version)} | {markdown(names)} | {markdown(urls)} |")
PY
elif [[ -f apps/android-app/build.gradle.kts ]]; then
  echo "Android Gradle wrapper is not executable at $android_gradlew; unable to resolve transitive license metadata."
else
  echo "No Android build.gradle.kts found."
fi

echo
echo "## Repository Licenses"
echo
for file in LICENSE third_party/openwire/LICENSE; do
  if [[ -f "$file" ]]; then
    echo "- $file"
  fi
done

echo
echo "## Release Review Notes"
echo
echo "- Android transitive dependency license names are generated from Gradle release runtime resolution and Maven POM metadata."
echo "- Verify Swift package license texts before submission."
echo "- Do not include read-only reference-project dependencies from references/fluxdo in Fire's shipped license list unless they are actually shipped."
