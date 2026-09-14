#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查MP3文件是否包含嵌入的歌词（ID3标签）
"""

import os
import sys
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, USLT

def check_mp3_lyrics(file_path):
    """检查MP3文件是否包含歌词"""
    try:
        audio = MP3(file_path, ID3=ID3)
        
        filename = os.path.basename(file_path)
        has_lyrics = False
        
        # 检查USLT (Unsynchronized Lyrics) 标签
        if audio.tags:
            for tag in audio.tags.values():
                if isinstance(tag, USLT):
                    has_lyrics = True
                    print(f"✅ {filename}")
                    print(f"   语言: {tag.lang}")
                    print(f"   描述: {tag.desc}")
                    lyrics_preview = tag.text[:100] if len(tag.text) > 100 else tag.text
                    print(f"   歌词预览: {lyrics_preview}...")
                    print()
                    return True
            
            # 检查其他可能的歌词标签
            for key in audio.tags.keys():
                if 'USLT' in str(key) or 'lyrics' in str(key).lower():
                    has_lyrics = True
                    print(f"✅ {filename}")
                    print(f"   找到歌词标签: {key}")
                    print()
                    return True
        
        if not has_lyrics:
            print(f"❌ {filename} - 无歌词")
        
        return has_lyrics
        
    except Exception as e:
        print(f"⚠️  {os.path.basename(file_path)} - 读取失败: {e}")
        return False

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='检查MP3文件是否包含ID3歌词')
    parser.add_argument('-d', '--directory', 
                       default='/Users/lzz/Downloads/AudioSampleBuffer-main/AudioSampleBuffer/Audio',
                       help='要扫描的目录路径')
    parser.add_argument('-f', '--file',
                       help='检查单个文件')
    
    args = parser.parse_args()
    
    print("🎵 MP3歌词检查工具")
    print("=" * 60)
    print()
    
    if args.file:
        # 检查单个文件
        if os.path.isfile(args.file):
            check_mp3_lyrics(args.file)
        else:
            print(f"❌ 文件不存在: {args.file}")
            return
    else:
        # 扫描目录
        directory = args.directory
        
        if not os.path.isdir(directory):
            print(f"❌ 目录不存在: {directory}")
            return
        
        print(f"📁 扫描目录: {directory}")
        print()
        
        mp3_files = [f for f in os.listdir(directory) if f.endswith('.mp3')]
        
        if not mp3_files:
            print("未找到MP3文件")
            return
        
        has_lyrics_count = 0
        total_count = len(mp3_files)
        
        for mp3_file in sorted(mp3_files):
            file_path = os.path.join(directory, mp3_file)
            if check_mp3_lyrics(file_path):
                has_lyrics_count += 1
        
        print("=" * 60)
        print(f"📊 统计结果:")
        print(f"   总文件数: {total_count}")
        print(f"   包含歌词: {has_lyrics_count}")
        print(f"   无歌词: {total_count - has_lyrics_count}")

if __name__ == '__main__':
    main()

