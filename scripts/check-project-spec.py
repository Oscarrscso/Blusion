#!/usr/bin/env python3
"""Static checks on project.yml (and its opt-in fallback overlay) that need no Xcode.

XcodeGen itself only runs on macOS in this project, so this catches the mistakes that can be caught anywhere: invalid YAML,
missing targets, dangling local package paths, and the App Transport Security rules from PLAN §1. Needs PyYAML; skips (exit 0) without it.
"""
import os
import sys

try:
    import yaml
except ImportError:
    print("check-project-spec: PyYAML not installed, skipped")
    sys.exit(0)

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []


def load(text, label):
    try:
        return yaml.safe_load(text)
    except yaml.YAMLError as exc:
        errors.append(f"{label}: invalid YAML: {exc}")
        return None


def check(spec, label, fallback):
    if spec is None:
        return
    targets = spec.get("targets", {})
    for name in ("Blusion", "BlusionTests", "BlusionUITests"):
        if name not in targets:
            errors.append(f"{label}: missing target {name}")
    packages = spec.get("packages", {})
    for name, pkg in packages.items():
        path = pkg.get("path")
        if path and not os.path.isfile(os.path.join(root, path, "Package.swift")):
            errors.append(f"{label}: package {name} points at {path}, which has no Package.swift")
    app = targets.get("Blusion", {})
    deps = [d.get("package") for d in app.get("dependencies", []) if isinstance(d, dict)]
    for dep in deps:
        if dep not in packages:
            errors.append(f"{label}: Blusion depends on package {dep}, which is not declared")
    for required in ("StremioKit", "PlayerKit", "Persistence", "Features"):
        if required not in deps:
            errors.append(f"{label}: Blusion does not depend on {required}")
    if fallback != ("FallbackPlayer" in deps):
        errors.append(f"{label}: FallbackPlayer dependency {'missing' if fallback else 'present'} (expected fallback={fallback})")
    base = spec.get("settings", {}).get("base", {})
    if str(base.get("SWIFT_VERSION")) != "6.0":
        errors.append(f"{label}: SWIFT_VERSION must be 6.0 (PLAN §1)")
    if base.get("SWIFT_STRICT_CONCURRENCY") != "complete":
        errors.append(f"{label}: SWIFT_STRICT_CONCURRENCY must be complete")
    flags = app.get("settings", {}).get("base", {}).get("OTHER_SWIFT_FLAGS", "")
    if fallback != ("BLUSION_FALLBACK_ENGINE" in str(flags)):
        errors.append(f"{label}: BLUSION_FALLBACK_ENGINE flag mismatch (expected fallback={fallback})")
    props = app.get("info", {}).get("properties", {})
    ats = props.get("NSAppTransportSecurity", {})
    if "NSAllowsArbitraryLoads" in ats:
        errors.append(f"{label}: NSAllowsArbitraryLoads must never be set (PLAN §1)")
    if ats.get("NSAllowsLocalNetworking") is not True:
        errors.append(f"{label}: NSAllowsLocalNetworking must be true (M2)")
    if ats.get("NSAllowsArbitraryLoadsForMedia") is not True:
        errors.append(f"{label}: NSAllowsArbitraryLoadsForMedia must be true (M5, ADR-005)")
    if "audio" not in props.get("UIBackgroundModes", []):
        errors.append(f"{label}: UIBackgroundModes must include audio (M5)")
    if not props.get("NSLocalNetworkUsageDescription"):
        errors.append(f"{label}: NSLocalNetworkUsageDescription is required (M2)")
    for needle in ("stremio",):
        for key in ("PRODUCT_BUNDLE_IDENTIFIER",):
            value = str(app.get("settings", {}).get("base", {}).get(key, "")).lower()
            if needle in value:
                errors.append(f"{label}: bundle id must not contain '{needle}' (PLAN §1 trademark rule)")
        if needle in str(spec.get("name", "")).lower() or needle in str(props.get("CFBundleDisplayName", "")).lower():
            errors.append(f"{label}: app name must not contain '{needle}' (PLAN §1 trademark rule)")


# The fallback engine must use the LGPL build of MPVKit, never the GPL one (docs/licenses.md).
fallback_manifest = os.path.join(root, "Packages", "FallbackPlayer", "Package.swift")
if os.path.isfile(fallback_manifest):
    manifest_text = open(fallback_manifest, encoding="utf-8").read()
    if "MPVKit-GPL" in manifest_text or "-GPL" in manifest_text:
        errors.append("Packages/FallbackPlayer/Package.swift references a GPL product; only the LGPL build may be linked (docs/licenses.md)")

text = open(os.path.join(root, "project.yml"), encoding="utf-8").read()
check(load(text, "project.yml"), "project.yml", fallback=False)
check(load(text.replace("#fallback# ", ""), "fallback overlay"), "fallback overlay", fallback=True)

if errors:
    print("check-project-spec: FAILED")
    for error in errors:
        print("  -", error)
    sys.exit(1)
print("check-project-spec: project.yml and the fallback overlay are consistent")
