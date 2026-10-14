#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Native XCTest entry point for environments where SwiftPM cannot nest its sandbox.
knock_checks_dir=$(mktemp -d /private/tmp/Knock-checks.XXXXXX)
knock_platform=$(xcrun --sdk macosx --show-sdk-platform-path)
knock_test_lib="$knock_platform/Developer/usr/lib"
knock_test_frameworks="$knock_platform/Developer/Library/Frameworks"
knock_test_bundle="$knock_checks_dir/DetectorCoreTests.xctest"
knock_compile=(-parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos14.0"
  -module-cache-path "$knock_checks_dir/ModuleCache")
knock_sources=(Knock/Models/KnockAction.swift Knock/Services/*.swift)
mkdir -p "$knock_test_bundle/Contents/MacOS"

xcrun swiftc "${knock_compile[@]}" -enable-testing -emit-module -emit-library \
  -module-name KnockCore "${knock_sources[@]}" \
  -emit-module-path "$knock_checks_dir/KnockCore.swiftmodule" \
  -o "$knock_checks_dir/libKnockCore.dylib"
xcrun swiftc "${knock_compile[@]}" -emit-library -module-name DetectorCoreTests \
  -I "$knock_checks_dir" -L "$knock_checks_dir" -lKnockCore \
  -I "$knock_test_lib" -L "$knock_test_lib" -F "$knock_test_frameworks" \
  -Xlinker -rpath -Xlinker "$knock_checks_dir" \
  -Xlinker -rpath -Xlinker "$knock_test_lib" \
  -Xlinker -rpath -Xlinker "$knock_test_frameworks" \
  Tests/DetectorCoreTests.swift Tests/AccelerometerTests.swift Tests/StrokeTests.swift \
  -o "$knock_test_bundle/Contents/MacOS/DetectorCoreTests"
cat > "$knock_test_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DetectorCoreTests</string>
<key>CFBundleIdentifier</key><string>dev.local.Knock.DetectorCoreTests</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
xcrun xctest "$knock_test_bundle"
xcrun swiftc "${knock_compile[@]}" "${knock_sources[@]}" Tests/ActionMappingChecks.swift \
  -o "$knock_checks_dir/ActionMappingChecks"
"$knock_checks_dir/ActionMappingChecks"
echo "Check artifacts: $knock_checks_dir"
