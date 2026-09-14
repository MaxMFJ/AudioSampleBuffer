#!/bin/bash
# 批量提取NCM歌词脚本

echo "🎵 批量歌词提取工具"
echo "===================="

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 网易云音乐目录
NETEASE_DIR="/Users/lzz/Music/网易云音乐"
# 项目Audio目录
PROJECT_AUDIO_DIR="/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio"

# 检查目录是否存在
if [ ! -d "$NETEASE_DIR" ]; then
    echo "❌ 错误: 网易云音乐目录不存在: $NETEASE_DIR"
    exit 1
fi

if [ ! -d "$PROJECT_AUDIO_DIR" ]; then
    echo "❌ 错误: 项目Audio目录不存在: $PROJECT_AUDIO_DIR"
    exit 1
fi

# 1. 批量处理NCM文件
echo ""
echo "${BLUE}步骤1: 处理NCM文件...${NC}"
python3 ncm_lyrics_extractor.py -d "$NETEASE_DIR" -r

# 2. 复制LRC文件到项目
echo ""
echo "${BLUE}步骤2: 复制歌词文件到项目...${NC}"

# 统计
copied_count=0
total_lrc=0

# 查找所有LRC文件
while IFS= read -r lrc_file; do
    ((total_lrc++))
    filename=$(basename "$lrc_file")
    
    # 检查是否有对应的MP3文件
    mp3_name="${filename%.lrc}.mp3"
    if [ -f "$PROJECT_AUDIO_DIR/$mp3_name" ]; then
        cp "$lrc_file" "$PROJECT_AUDIO_DIR/"
        echo "${GREEN}✓${NC} 复制: $filename"
        ((copied_count++))
    else
        echo "${YELLOW}⊘${NC} 跳过: $filename (无对应MP3)"
    fi
done < <(find "$NETEASE_DIR" -name "*.lrc" -type f)

# 3. 统计结果
echo ""
echo "===================="
echo "${GREEN}完成！${NC}"
echo "  找到LRC文件: $total_lrc 个"
echo "  复制到项目: $copied_count 个"
echo ""
echo "现在可以在Xcode中运行项目测试歌词功能了！"
echo ""

# 4. 列出项目中的歌词文件
echo "${BLUE}项目中的歌词文件：${NC}"
ls -1 "$PROJECT_AUDIO_DIR"/*.lrc 2>/dev/null | while read lrc; do
    basename "$lrc"
done

echo ""
echo "💡 提示："
echo "  - 在Xcode中将这些.lrc文件添加到项目"
echo "  - 确保Target Membership勾选了AudioSampleBuffer"
echo "  - 运行项目，播放有歌词的歌曲即可看到歌词显示"

