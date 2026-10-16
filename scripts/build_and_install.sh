#!/bin/bash
#
# Собирает CopyPaste, подписывает локальным сертификатом и устанавливает в /Applications.
#
# Сертификат важен: разрешение «Универсальный доступ» macOS привязывает к подписи
# приложения. При ad-hoc подписи она меняется на каждой сборке и разрешение
# приходится выдавать заново; при подписи сертификатом — остаётся действующим.
#
# Один раз нужно создать сертификат (см. README, раздел «Подпись»).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="CopyPaste Local Signing"
DEST="/Applications/CopyPaste.app"
BUILD="$ROOT/build/macos/Build/Products/Release/CopyPaste.app"

cd "$ROOT"
flutter build macos --release

pkill -f "CopyPaste.app/Contents/MacOS/CopyPaste" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$BUILD" "$DEST"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep --sign "$IDENTITY" "$DEST"
  echo "подписано сертификатом: $IDENTITY"
else
  echo "ВНИМАНИЕ: сертификат «$IDENTITY» не найден — приложение осталось с ad-hoc подписью,"
  echo "разрешение «Универсальный доступ» придётся выдать заново после этой сборки."
fi

open -n "$DEST"
echo "установлено и запущено: $DEST"
