#!/bin/bash
# QQ音乐歌词获取测试脚本

echo "🎵 QQ音乐歌词获取测试"
echo "=========================="
echo ""

# 检查依赖
if ! command -v ffmpeg &> /dev/null; then
    echo "❌ 未安装 ffmpeg"
    echo "请运行: brew install ffmpeg"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "❌ 未安装 python3"
    exit 1
fi

# 检查 mutagen 库
if ! python3 -c "import mutagen" 2>/dev/null; then
    echo "❌ 未安装 mutagen 库"
    echo "请运行: pip3 install mutagen"
    exit 1
fi

echo "✅ 所有依赖已安装"
echo ""

# 测试用例 1: 检查 OGG 文件元数据
if [ -f "$1" ]; then
    echo "📂 测试文件: $1"
    echo ""
    
    # 运行检查脚本
    python3 "$(dirname "$0")/check_qqmusic_metadata.py" "$1"
    
    # 询问是否转换
    echo ""
    read -p "是否转换为 MP3 并保留元数据? (y/n): " answer
    
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        output_file="${1%.ogg}.mp3"
        echo ""
        echo "🔄 正在转换..."
        
        ffmpeg -i "$1" \
               -c:a libmp3lame \
               -q:a 2 \
               -map_metadata 0 \
               -id3v2_version 3 \
               -y \
               "$output_file" \
               2>&1 | grep -E "Duration|Output|error"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✅ 转换完成: $output_file"
            echo ""
            echo "📊 检查转换后的元数据:"
            echo "------------------------"
            python3 "$(dirname "$0")/check_qqmusic_metadata.py" "$output_file"
        else
            echo "❌ 转换失败"
        fi
    fi
else
    echo "使用方法: $0 <ogg文件路径>"
    echo ""
    echo "示例:"
    echo "  $0 song.ogg"
    echo "  $0 /path/to/music/七里香.ogg"
fi

echo ""
echo "=========================="
echo "💡 提示:"
echo "  1. 如果文件包含 songmid，可以用它获取歌词"
echo "  2. 转换后的 MP3 文件会保留所有元数据"
echo "  3. 在 iOS 项目中导入 MP3 后可自动获取歌词"

