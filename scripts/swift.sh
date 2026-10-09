#!/bin/zsh
# Runs `swift <args>` working around two stale files some Command Line Tools installs ship:
#   - ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface (2024) breaks Package.swift
#   - usr/include/swift/module.modulemap (2023) redefines SwiftBridging
# Neither is touched; a clean copy / VFS overlay is used instead. Delete .swiftpm-libs to regenerate.
set -euo pipefail
ROOT="${0:A:h:h}"
CLT=/Library/Developer/CommandLineTools
LIBS="$ROOT/.swiftpm-libs"
extra=()

if [[ "$(xcode-select -p)" == "$CLT" ]]; then
  if ls "$CLT"/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface(N) | grep -q .; then
    if [[ ! -d "$LIBS/ManifestAPI" ]]; then
      mkdir -p "$LIBS"
      cp -R "$CLT/usr/lib/swift/pm/" "$LIBS/"
      find "$LIBS" -name "*.private.swiftinterface" -delete
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$LIBS"
  fi
  if [[ -f "$CLT/usr/include/swift/module.modulemap" && -f "$CLT/usr/include/swift/bridging.modulemap" ]]; then
    mkdir -p "$LIBS/overlay"
    print -- "// hides stale CLT module.modulemap" > "$LIBS/overlay/empty.modulemap"
    cat > "$LIBS/overlay/vfs.yaml" <<YAML
{"version": 0, "case-sensitive": "false", "roots": [{"type": "directory",
 "name": "$CLT/usr/include/swift",
 "contents": [{"type": "file", "name": "module.modulemap", "external-contents": "$LIBS/overlay/empty.modulemap"}]}]}
YAML
    extra=(-Xswiftc -vfsoverlay -Xswiftc "$LIBS/overlay/vfs.yaml" -Xcc -ivfsoverlay -Xcc "$LIBS/overlay/vfs.yaml")
  fi
fi

cmd="$1"; shift
case "$cmd" in
  build|test|run) exec swift "$cmd" --package-path "$ROOT" "${extra[@]}" "$@" ;;
  *) exec swift "$cmd" --package-path "$ROOT" "$@" ;;
esac
