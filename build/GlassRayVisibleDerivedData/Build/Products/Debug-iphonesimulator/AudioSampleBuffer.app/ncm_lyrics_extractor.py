#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NCM歌词提取工具 & 网易云音乐歌词下载器

功能：
1. 从NCM文件中提取元数据和歌词
2. 从网易云音乐API下载歌词
3. 批量处理整个音乐文件夹

使用方法：
    python3 ncm_lyrics_extractor.py --help
"""

import struct
import binascii
import base64
import json
import os
import sys
import argparse
import requests
from pathlib import Path
from Crypto.Cipher import AES


class NCMFile:
    """NCM文件解析器"""
    
    CORE_KEY = binascii.a2b_hex("687A4852416D736F356B496E62617857")
    META_KEY = binascii.a2b_hex("2331346C6A6B5F215C5D2630553C2728")
    
    def __init__(self, filepath):
        self.filepath = filepath
        self.metadata = None
        self.music_id = None
        
    def decrypt(self):
        """解密NCM文件并提取元数据"""
        try:
            with open(self.filepath, 'rb') as f:
                # 检查文件头
                header = f.read(8)
                if header != b'CTENFDAM':
                    print(f"错误: {self.filepath} 不是有效的NCM文件")
                    return False
                
                f.seek(2, 1)  # 跳过2字节
                
                # 读取密钥数据
                key_length = struct.unpack('<I', f.read(4))[0]
                key_data = bytearray(f.read(key_length))
                
                # 解密密钥
                for i in range(len(key_data)):
                    key_data[i] ^= 0x64
                
                # 读取元数据
                meta_length = struct.unpack('<I', f.read(4))[0]
                meta_data = bytearray(f.read(meta_length))
                
                # 解密元数据
                for i in range(len(meta_data)):
                    meta_data[i] ^= 0x63
                
                # Base64解码
                meta_data = base64.b64decode(meta_data[22:])
                
                # AES解密元数据
                cipher = AES.new(self.META_KEY, AES.MODE_ECB)
                meta_data = cipher.decrypt(meta_data)
                
                # 去除PKCS7填充
                meta_data = meta_data[:-meta_data[-1]]
                
                # 解析JSON
                meta_json = meta_data.decode('utf-8')
                meta_json = meta_json[6:]  # 去除 "music:" 前缀
                
                self.metadata = json.loads(meta_json)
                self.music_id = str(self.metadata.get('musicId', ''))
                
                return True
                
        except Exception as e:
            print(f"解析NCM文件失败: {e}")
            return False
    
    def get_music_info(self):
        """获取音乐信息"""
        if not self.metadata:
            return None
        
        return {
            'id': self.music_id,
            'name': self.metadata.get('musicName', ''),
            'artist': ', '.join([a[0] for a in self.metadata.get('artist', [])]),
            'album': self.metadata.get('album', ''),
            'format': self.metadata.get('format', 'mp3')
        }


class NeteaseLyricsDownloader:
    """网易云音乐歌词下载器"""
    
    API_URL = "https://music.163.com/api/song/lyric"
    
    @staticmethod
    def download_lyrics(music_id):
        """下载歌词"""
        try:
            params = {
                'id': music_id,
                'lv': 1,
                'tv': -1
            }
            
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                'Referer': 'https://music.163.com/'
            }
            
            response = requests.get(
                NeteaseLyricsDownloader.API_URL,
                params=params,
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                
                if 'lrc' in data and 'lyric' in data['lrc']:
                    return data['lrc']['lyric']
                else:
                    print(f"该歌曲(ID: {music_id})暂无歌词")
                    return None
            else:
                print(f"请求失败: HTTP {response.status_code}")
                return None
                
        except requests.exceptions.RequestException as e:
            print(f"网络请求失败: {e}")
            return None
        except Exception as e:
            print(f"下载歌词失败: {e}")
            return None
    
    @staticmethod
    def save_lyrics(lyrics_content, output_path):
        """保存歌词到文件"""
        try:
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(lyrics_content)
            return True
        except Exception as e:
            print(f"保存歌词失败: {e}")
            return False


def process_ncm_file(ncm_path, output_dir=None):
    """处理单个NCM文件"""
    print(f"\n处理文件: {os.path.basename(ncm_path)}")
    
    # 解析NCM文件
    ncm = NCMFile(ncm_path)
    if not ncm.decrypt():
        return False
    
    info = ncm.get_music_info()
    if not info:
        print("  ✗ 无法获取音乐信息")
        return False
    
    print(f"  歌曲: {info['name']}")
    print(f"  艺术家: {info['artist']}")
    print(f"  专辑: {info['album']}")
    print(f"  网易云ID: {info['id']}")
    
    # 下载歌词
    if not info['id']:
        print("  ✗ 未找到歌曲ID")
        return False
    
    print(f"  正在下载歌词...")
    lyrics = NeteaseLyricsDownloader.download_lyrics(info['id'])
    
    if not lyrics:
        return False
    
    # 确定输出路径
    if output_dir is None:
        output_dir = os.path.dirname(ncm_path)
    
    # 生成LRC文件名
    ncm_filename = os.path.basename(ncm_path)
    lrc_filename = os.path.splitext(ncm_filename)[0] + '.lrc'
    lrc_path = os.path.join(output_dir, lrc_filename)
    
    # 保存歌词
    if NeteaseLyricsDownloader.save_lyrics(lyrics, lrc_path):
        print(f"  ✓ 歌词已保存: {lrc_filename}")
        return True
    else:
        return False


def process_directory(directory, recursive=False):
    """批量处理目录中的NCM文件"""
    directory = Path(directory)
    
    if not directory.exists():
        print(f"错误: 目录不存在: {directory}")
        return
    
    # 查找NCM文件
    if recursive:
        ncm_files = list(directory.rglob('*.ncm'))
    else:
        ncm_files = list(directory.glob('*.ncm'))
    
    if not ncm_files:
        print(f"未找到NCM文件")
        return
    
    print(f"找到 {len(ncm_files)} 个NCM文件")
    
    success_count = 0
    for ncm_file in ncm_files:
        if process_ncm_file(str(ncm_file)):
            success_count += 1
    
    print(f"\n完成! 成功: {success_count}/{len(ncm_files)}")


def download_lyrics_by_id(music_id, output_path=None):
    """根据歌曲ID下载歌词"""
    print(f"正在下载歌曲 {music_id} 的歌词...")
    
    lyrics = NeteaseLyricsDownloader.download_lyrics(music_id)
    
    if not lyrics:
        return False
    
    if output_path:
        if NeteaseLyricsDownloader.save_lyrics(lyrics, output_path):
            print(f"✓ 歌词已保存: {output_path}")
            return True
        else:
            return False
    else:
        print("\n" + "="*50)
        print(lyrics)
        print("="*50)
        return True


def main():
    parser = argparse.ArgumentParser(
        description='NCM歌词提取工具 & 网易云音乐歌词下载器',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
示例:
  # 处理单个NCM文件
  python3 ncm_lyrics_extractor.py -f "music.ncm"
  
  # 批量处理文件夹
  python3 ncm_lyrics_extractor.py -d "/Users/xxx/Music/网易云音乐"
  
  # 递归处理子文件夹
  python3 ncm_lyrics_extractor.py -d "/Users/xxx/Music" -r
  
  # 根据歌曲ID下载歌词
  python3 ncm_lyrics_extractor.py --id 1234567890 -o "lyrics.lrc"
        '''
    )
    
    parser.add_argument('-f', '--file', help='NCM文件路径')
    parser.add_argument('-d', '--directory', help='包含NCM文件的目录')
    parser.add_argument('-r', '--recursive', action='store_true', help='递归处理子目录')
    parser.add_argument('--id', help='网易云音乐歌曲ID')
    parser.add_argument('-o', '--output', help='输出文件路径')
    
    args = parser.parse_args()
    
    # 检查是否安装了依赖
    try:
        import requests
        from Crypto.Cipher import AES
    except ImportError as e:
        print("错误: 缺少必要的依赖库")
        print("\n请运行以下命令安装:")
        print("  pip3 install pycryptodome requests")
        sys.exit(1)
    
    # 处理不同的模式
    if args.file:
        process_ncm_file(args.file, os.path.dirname(args.output) if args.output else None)
    elif args.directory:
        process_directory(args.directory, args.recursive)
    elif args.id:
        download_lyrics_by_id(args.id, args.output)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()

