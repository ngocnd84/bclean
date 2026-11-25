#!/bin/bash
# Tạo file Xcode project cho Bclean và mở Xcode. Chạy 1 lần trên MacBook:
#   cd Bclean && bash setup.sh
set -e
cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "❌ Chưa có Xcode. Cài Xcode từ Mac App Store rồi chạy lại."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "❌ Chưa có Homebrew. Cài tại https://brew.sh (copy 1 dòng lệnh trên trang đó), rồi chạy lại."
    exit 1
  fi
  echo "→ Đang cài XcodeGen..."
  brew install xcodegen
fi

echo "→ Đang tạo Bclean.xcodeproj..."
xcodegen generate
echo "✅ Xong. Đang mở Xcode..."
open Bclean.xcodeproj
