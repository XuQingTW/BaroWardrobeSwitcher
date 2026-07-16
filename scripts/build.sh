#!/usr/bin/env sh
set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: build.sh <BarotraumaInstallDir> <LuaCsPublicizedDir> [MonoGameAssemblyPath]" >&2
  exit 64
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BAROTRAUMA_DIR=$1
PUBLICIZED_DIR=$2
MONOGAME_PATH=${3:-}

set -- dotnet build "$ROOT/CSharp/BaroWardrobeSwitcher.csproj" -c Release \
  "-p:BarotraumaInstallDir=$BAROTRAUMA_DIR" \
  "-p:LuaCsPublicizedDir=$PUBLICIZED_DIR"

if [ -n "$MONOGAME_PATH" ]; then
  set -- "$@" "-p:MonoGameAssemblyPath=$MONOGAME_PATH"
fi

exec "$@"
