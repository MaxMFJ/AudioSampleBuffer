#!/bin/bash
# 将LRC文件同步到iOS应用沙盒（模拟器）

echo "🎵 歌词同步工具 - 同步到iOS沙盒"
echo "=========================================="

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 源目录（项目Audio目录）
SOURCE_DIR="/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio"

# 查找模拟器的沙盒目录
# 注意：这需要应用已经运行过至少一次
APP_BUNDLE_ID="com.yourcompany.AudioSampleBuffer"  # 替换为实际的Bundle ID

echo "${BLUE}查找应用沙盒目录...${NC}"

# 查找最新的模拟器设备目录
SIMULATOR_DIR=$(find ~/Library/Developer/CoreSimulator/Devices -name "AudioSampleBuffer.app" -type d 2>/dev/null | head -1)

if [ -z "$SIMULATOR_DIR" ]; then
    echo "${RED}❌ 未找到应用沙盒目录${NC}"
    echo "请确保："
    echo "  1. 应用已经在模拟器中运行过"
    echo "  2. Bundle ID 配置正确"
    echo ""
    echo "${YELLOW}💡 提示: 使用动态加载功能，歌词会自动保存到沙盒${NC}"
    exit 1
fi

# 获取容器目录
DEVICE_DIR=$(dirname $(dirname "$SIMULATOR_DIR"))
CONTAINER_DIR=$(find "$DEVICE_DIR/data/Containers/Data/Application" -name "Documents" -type d 2>/dev/null | head -1)

if [ -z "$CONTAINER_DIR" ]; then
    echo "${RED}❌ 未找到Documents目录${NC}"
    exit 1
fi

LYRICS_SANDBOX_DIR="$CONTAINER_DIR/Lyrics"

echo "${GREEN}✓${NC} 找到沙盒目录: $LYRICS_SANDBOX_DIR"

# 创建Lyrics目录
mkdir -p "$LYRICS_SANDBOX_DIR"

# 复制LRC文件
echo ""
echo "${BLUE}同步歌词文件...${NC}"

copied_count=0

for lrc_file in "$SOURCE_DIR"/*.lrc; do
    if [ -f "$lrc_file" ]; then
        filename=$(basename "$lrc_file")
        cp "$lrc_file" "$LYRICS_SANDBOX_DIR/"
        echo "${GREEN}✓${NC} $filename"
        ((copied_count++))
    fi
done

echo ""
echo "=========================================="
echo "${GREEN}完成！${NC}"
echo "  已同步 $copied_count 个歌词文件"
echo ""
echo "${YELLOW}💡 现在LyricsManager会自动从沙盒加载这些歌词${NC}"

