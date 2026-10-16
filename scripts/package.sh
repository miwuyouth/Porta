#!/bin/bash
set -eo pipefail

# ==========================================================
# Porta macOS 应用打包脚本
# 支持在本地及 CI 环境中运行，自动注入版本号与 Git Commit ID
# ==========================================================

# 1. 计算版本号
if [ -n "$1" ]; then
    VERSION="$1"
elif [ -n "$APP_VERSION" ]; then
    VERSION="$APP_VERSION"
else
    # 尝试从当前 git tag 获取
    GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
    if [ -n "$GIT_TAG" ]; then
        VERSION="${GIT_TAG#v}"
    else
        VERSION="0.0.0-dev"
    fi
fi

# 2. 计算 Git Commit ID
SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    # 若有未提交修改，附带 + 标记
    COMMIT_ID="${SHORT_SHA}+"
else
    COMMIT_ID="${SHORT_SHA}"
fi

echo "=========================================="
echo "📦 正在打包 Porta macOS 应用"
echo "📌 版本号 (Marketing Version) : $VERSION"
echo "🔖 提交号 (Git Commit / Build): $COMMIT_ID"
echo "=========================================="

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 3. 检查并生成 Xcode 项目
if ! command -v xcodegen &> /dev/null; then
    echo "❌ 错误: 未检测到 xcodegen，请先执行: brew install xcodegen"
    exit 1
fi

echo "⚙️  生成 Xcode 项目..."
xcodegen generate

# 4. 编译 Release (Universal 2: arm64 + x86_64)
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "🔨 正在编译 Release 应用 (Universal 2: arm64 + x86_64)..."
if command -v xcbeautify &> /dev/null; then
    xcodebuild clean build \
        -project Porta.xcodeproj \
        -scheme Porta \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$COMMIT_ID" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        | xcbeautify
else
    xcodebuild clean build \
        -project Porta.xcodeproj \
        -scheme Porta \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$COMMIT_ID" \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO
fi

APP_PATH="$BUILD_DIR/Build/Products/Release/Porta.app"
BIN_PATH="$APP_PATH/Contents/MacOS/Porta"

if [ ! -d "$APP_PATH" ] || [ ! -f "$BIN_PATH" ]; then
    echo "❌ 编译产物不存在或缺失主可执行文件: $BIN_PATH"
    exit 1
fi

echo "🔏 正在执行 Ad-hoc 代码签名..."
codesign --force --deep --sign - "$APP_PATH"
codesign -v "$APP_PATH"
echo "✅ 代码签名验证通过"

# 5. 校验 Info.plist 中的版本信息
INFOPLIST="$APP_PATH/Contents/Info.plist"
VER_CHECK=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFOPLIST")
BUILD_CHECK=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFOPLIST")
echo "✅ 产物 Info.plist 验证通过: 版本 $VER_CHECK ($BUILD_CHECK)"

# 6. 复制 App 到 dist
cp -R "$APP_PATH" "$DIST_DIR/Porta.app"

# 7. 打包 ZIP
ZIP_NAME="Porta-${VERSION}-${SHORT_SHA}.zip"
echo "📦 正在制作 ZIP 压缩包: $ZIP_NAME..."
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/Porta.app" "$DIST_DIR/$ZIP_NAME"

# 8. 打包 DMG
DMG_NAME="Porta-${VERSION}.dmg"
echo "💿 正在制作 DMG 镜像: $DMG_NAME..."
DMG_TEMP="$BUILD_DIR/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"
cp -R "$DIST_DIR/Porta.app" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "Porta" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DIST_DIR/$DMG_NAME" > /dev/null

rm -rf "$DMG_TEMP"

echo "=========================================="
echo "🎉 打包完成！生成文件如下："
ls -lh "$DIST_DIR"
echo "=========================================="
