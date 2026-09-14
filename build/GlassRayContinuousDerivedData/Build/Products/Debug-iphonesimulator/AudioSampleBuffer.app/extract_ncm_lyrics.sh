#!/bin/bash
# NCM 歌词批量提取工具
# 从网易云音乐 NCM 文件中提取内嵌的 LRC 歌词

set -e

echo "🎵 NCM 歌词批量提取工具"
echo "========================================"
echo ""

# 配置
SOURCE_DIR="${1:-$HOME/Music/网易云音乐}"
OUTPUT_DIR="${2:-$PWD/AudioSampleBuffer/Audio}"
LYRICS_DIR="$OUTPUT_DIR"

# 检查源目录
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ 源目录不存在: $SOURCE_DIR"
    echo ""
    echo "使用方法:"
    echo "  $0 [NCM文件目录] [输出目录]"
    echo ""
    echo "示例:"
    echo "  $0 ~/Music/网易云音乐 AudioSampleBuffer/Audio"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$LYRICS_DIR"

echo "📂 源目录: $SOURCE_DIR"
echo "💾 输出目录: $OUTPUT_DIR"
echo "📝 歌词目录: $LYRICS_DIR"
echo ""

# 查找所有 NCM 文件
echo "🔍 扫描 NCM 文件..."
NCM_FILES=($(find "$SOURCE_DIR" -name "*.ncm" 2>/dev/null))

if [ ${#NCM_FILES[@]} -eq 0 ]; then
    echo "❌ 未找到 NCM 文件"
    exit 1
fi

echo "✅ 找到 ${#NCM_FILES[@]} 个 NCM 文件"
echo ""
echo "========================================"
echo "开始提取歌词..."
echo "========================================"
echo ""

SUCCESS_COUNT=0
LYRICS_COUNT=0
NO_LYRICS_COUNT=0

# 使用 Python 脚本提取歌词
python3 << 'PYTHON_EOF'
import sys
import os
import json
import base64
import struct
from pathlib import Path

# NCM 解密密钥
CORE_KEY = bytes([
    0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
    0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57
])

META_KEY = bytes([
    0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
    0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28
])

def aes_ecb_decrypt(data, key):
    from Crypto.Cipher import AES
    cipher = AES.new(key, AES.MODE_ECB)
    return cipher.decrypt(data)

def extract_metadata(ncm_path):
    try:
        with open(ncm_path, 'rb') as f:
            # 验证文件头
            header = f.read(8)
            if header != b'CTENFDAM':
                return None
            
            # 跳过 2 字节
            f.read(2)
            
            # 读取密钥长度并跳过密钥
            key_length = struct.unpack('<I', f.read(4))[0]
            f.read(key_length)
            
            # 读取元数据长度
            meta_length = struct.unpack('<I', f.read(4))[0]
            if meta_length == 0:
                return None
            
            # 读取元数据
            encrypted_meta = bytearray(f.read(meta_length))
            
            # XOR with 0x63
            for i in range(len(encrypted_meta)):
                encrypted_meta[i] ^= 0x63
            
            # 去除前缀
            base64_data = bytes(encrypted_meta[22:])
            
            # Base64 解码
            json_data = base64.b64decode(base64_data)
            
            # AES 解密
            decrypted = aes_ecb_decrypt(json_data, META_KEY)
            
            # 去除 "music:" 前缀和 padding
            meta_json = decrypted[6:].rstrip(b'\x00').rstrip(b'\x10').rstrip(b'\x0f').rstrip(b'\x0e').rstrip(b'\x0d').rstrip(b'\x0c').rstrip(b'\x0b').rstrip(b'\x0a').rstrip(b'\t').rstrip(b'\x08').rstrip(b'\x07').rstrip(b'\x06').rstrip(b'\x05').rstrip(b'\x04').rstrip(b'\x03').rstrip(b'\x02').rstrip(b'\x01')
            
            # JSON 解析
            metadata = json.loads(meta_json)
            return metadata
            
    except Exception as e:
        print(f"   ⚠️  解析失败: {e}")
        return None

def save_lyrics(metadata, ncm_path, lyrics_dir):
    if not metadata or 'lyric' not in metadata:
        return False
    
    lyrics = metadata['lyric']
    if not lyrics:
        return False
    
    # 构建文件名
    artist = metadata.get('artist', [['']])[0][0] if metadata.get('artist') else ''
    song_name = metadata.get('musicName', '')
    
    filename = Path(ncm_path).stem
    if artist and song_name:
        filename = f"{artist}-{song_name}"
    
    lrc_path = os.path.join(lyrics_dir, f"{filename}.lrc")
    
    # 保存歌词
    with open(lrc_path, 'w', encoding='utf-8') as f:
        f.write(lyrics)
    
    print(f"   ✅ {filename}.lrc")
    return True

# 主处理逻辑
ncm_files = os.environ.get('NCM_FILES', '').split('\n')
lyrics_dir = os.environ.get('LYRICS_DIR', '')

success = 0
has_lyrics = 0

for ncm_file in ncm_files:
    if not ncm_file or not ncm_file.endswith('.ncm'):
        continue
    
    filename = os.path.basename(ncm_file)
    print(f"📀 {filename}")
    
    metadata = extract_metadata(ncm_file)
    if metadata and save_lyrics(metadata, ncm_file, lyrics_dir):
        success += 1
        has_lyrics += 1
    else:
        print(f"   ⚠️  无歌词")

print(f"\n✅ 提取完成: {success}/{len([f for f in ncm_files if f])} 个文件包含歌词")
PYTHON_EOF

echo ""
echo "========================================"
echo "📊 统计结果:"
echo "   总文件数: ${#NCM_FILES[@]}"
echo "   包含歌词: 检查上方输出"
echo "   保存目录: $LYRICS_DIR"
echo "========================================"
echo ""
echo "✅ 完成！歌词文件已保存到: $LYRICS_DIR/*.lrc"

