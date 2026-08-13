#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
IMPORT = re.compile(r"^\s*(?:@_exported\s+)?import(?:\s+(?:class|enum|func|protocol|struct|typealias|var))?\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)

ALLOWED_IMPORTS = {
    "TrainingDomain": set(),
    "TrainingInsights": {"TrainingDomain"},
    "TrainingApplication": {"CryptoKit", "Foundation", "TrainingDomain", "TrainingInsights"},
    "TrainingPersistence": {"Foundation", "GRDB", "TrainingApplication"},
    "HealthKitAdapter": {"HealthKit", "TrainingApplication"},
}

EXPECTED_TARGET_DEPENDENCIES = {
    "TrainingDomain": set(),
    "TrainingInsights": {"TrainingDomain"},
    "TrainingApplication": {"TrainingDomain", "TrainingInsights"},
    "TrainingPersistence": {"GRDB", "TrainingApplication"},
    "HealthKitAdapter": {"TrainingApplication"},
}

EXPECTED_MODULES = set(EXPECTED_TARGET_DEPENDENCIES)


def dependency_name(raw: dict[str, object]) -> str | None:
    for value in raw.values():
        if isinstance(value, list) and value and isinstance(value[0], str):
            return value[0]
        if isinstance(value, dict):
            name = value.get("name")
            if isinstance(name, str):
                return name
    return None


errors: list[str] = []
for module, allowed in ALLOWED_IMPORTS.items():
    directory = ROOT / "Sources" / module
    for source in sorted(directory.rglob("*.swift")):
        for imported in IMPORT.findall(source.read_text()):
            if imported not in allowed:
                errors.append(f"{source.relative_to(ROOT)} imports forbidden module {imported}")

package = json.loads(
    subprocess.check_output(["swift", "package", "dump-package"], cwd=ROOT, text=True)
)
for dependency in package["dependencies"]:
    if set(dependency) != {"sourceControl"}:
        errors.append("Only reviewed source-control dependencies are allowed")

allowed_target_types = {"regular", "executable", "test"}
for target in package["targets"]:
    if target["type"] not in allowed_target_types:
        errors.append(
            f"Swift package target {target['name']} has forbidden type {target['type']}"
        )
    for setting in target.get("settings", []):
        setting_text = json.dumps(setting, sort_keys=True).lower()
        if "link" in setting_text or "unsafe" in setting_text:
            errors.append(
                f"Swift package target {target['name']} has unreviewed linker setting {setting}"
            )

targets = {target["name"]: target for target in package["targets"]}
missing_modules = EXPECTED_MODULES - set(targets)
if missing_modules:
    errors.append(f"Required package modules are missing: {sorted(missing_modules)}")
for target_name, expected in EXPECTED_TARGET_DEPENDENCIES.items():
    actual = {
        name
        for raw in targets[target_name].get("dependencies", [])
        if (name := dependency_name(raw)) is not None
    }
    if actual != expected:
        errors.append(
            f"{target_name} dependencies are {sorted(actual)}, expected {sorted(expected)}"
        )

app_allowed = {
    "Foundation",
    "HealthKitAdapter",
    "Observation",
    "OSLog",
    "SwiftUI",
    "UIKit",
    "TrainingApplication",
    "TrainingPersistence",
}
for source in sorted((ROOT / "TrainingCompassApp").rglob("*.swift")):
    for imported in IMPORT.findall(source.read_text()):
        if imported not in app_allowed:
            errors.append(f"{source.relative_to(ROOT)} imports forbidden module {imported}")

project = (ROOT / "TrainingCompass.xcodeproj" / "project.pbxproj").read_text()
package_product_section = project.split(
    "/* Begin XCSwiftPackageProductDependency section */", maxsplit=1
)[1].split("/* End XCSwiftPackageProductDependency section */", maxsplit=1)[0]
linked_products = set(
    re.findall(r"productName = ([A-Za-z_][A-Za-z0-9_]*);", package_product_section)
)
allowed_linked_products = {"TrainingApplication", "TrainingPersistence", "HealthKitAdapter"}
if linked_products != allowed_linked_products:
    errors.append(
        f"Xcode linked products are {sorted(linked_products)}, expected {sorted(allowed_linked_products)}"
    )

binary_references = set(
    re.findall(
        r"(?:path|name) = [^;]*\.(?:framework|xcframework|a|dylib|tbd);",
        project,
    )
)
binary_file_types = set(
    re.findall(
        r"(?:explicitFileType|lastKnownFileType) = (?:wrapper\.(?:framework|xcframework)|archive\.ar|compiled\.mach-o\.dylib|sourcecode\.text-based-dylib-definition);",
        project,
    )
)
if binary_references or binary_file_types:
    errors.append(
        "Unexpected directly linked Xcode binaries: "
        f"references={sorted(binary_references)}, types={sorted(binary_file_types)}"
    )

if errors:
    print("Dependency boundary check failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print("Dependency boundaries are inward and framework-contained.")
