#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NCM增强歌词检查工具
分析NCM文件是否包含逐字歌词（.enhanced.lrc）

功能：
1. 从NCM文件中提取元数据
2. 检查网易云音乐API返回的所有歌词类型
3. 对比普通LRC和增强LRC的区别
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


class EnhancedLyricsChecker:
    """增强歌词检查器"""
    
    API_URL = "https://music.163.com/api/song/lyric"
    
    @staticmethod
    def get_all_lyrics_types(music_id):
        """获取所有类型的歌词"""
        try:
            params = {
                'id': music_id,
                'lv': 1,  # 歌词版本
                'tv': -1  # 翻译版本
            }
            
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
                'Referer': 'https://music.163.com/'
            }
            
            response = requests.get(
                EnhancedLyricsChecker.API_URL,
                params=params,
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                print(f"请求失败: HTTP {response.status_code}")
                return None
                
        except requests.exceptions.RequestException as e:
            print(f"网络请求失败: {e}")
            return None
        except Exception as e:
            print(f"获取歌词失败: {e}")
            return None
    
    @staticmethod
    def analyze_lyrics(data, save_samples=False, output_dir=None):
        """分析歌词数据"""
        print("\n" + "="*80)
        print("📊 歌词类型分析")
        print("="*80)
        
        results = {
            'has_lrc': False,
            'has_klyric': False,
            'has_tlyric': False,
            'has_romalrc': False,
            'has_yrc': False,
            'has_ytlrc': False,
            'has_yromalrc': False
        }
        
        # 1. 普通LRC歌词
        if 'lrc' in data and 'lyric' in data['lrc'] and data['lrc']['lyric']:
            results['has_lrc'] = True
            print("\n✅ 普通LRC歌词 (lrc.lyric)")
            print(f"   版本: {data['lrc'].get('version', 'N/A')}")
            lyrics_preview = data['lrc']['lyric'][:200] if len(data['lrc']['lyric']) > 200 else data['lrc']['lyric']
            print(f"   预览: {lyrics_preview}...")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'normal.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['lrc']['lyric'])
        else:
            print("\n❌ 无普通LRC歌词")
        
        # 2. 逐字歌词 (klyric) - 这是旧版的逐字歌词
        if 'klyric' in data and 'lyric' in data['klyric'] and data['klyric']['lyric']:
            results['has_klyric'] = True
            print("\n✅ 逐字歌词 (klyric.lyric) - 旧版格式")
            print(f"   版本: {data['klyric'].get('version', 'N/A')}")
            lyrics_preview = data['klyric']['lyric'][:200] if len(data['klyric']['lyric']) > 200 else data['klyric']['lyric']
            print(f"   预览: {lyrics_preview}...")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'word_by_word.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['klyric']['lyric'])
        else:
            print("\n❌ 无逐字歌词 (klyric)")
        
        # 3. 翻译歌词
        if 'tlyric' in data and 'lyric' in data['tlyric'] and data['tlyric']['lyric']:
            results['has_tlyric'] = True
            print("\n✅ 翻译歌词 (tlyric.lyric)")
            print(f"   版本: {data['tlyric'].get('version', 'N/A')}")
            lyrics_preview = data['tlyric']['lyric'][:200] if len(data['tlyric']['lyric']) > 200 else data['tlyric']['lyric']
            print(f"   预览: {lyrics_preview}...")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'translation.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['tlyric']['lyric'])
        else:
            print("\n❌ 无翻译歌词 (tlyric)")
        
        # 4. 罗马音歌词
        if 'romalrc' in data and 'lyric' in data['romalrc'] and data['romalrc']['lyric']:
            results['has_romalrc'] = True
            print("\n✅ 罗马音歌词 (romalrc.lyric)")
            print(f"   版本: {data['romalrc'].get('version', 'N/A')}")
            lyrics_preview = data['romalrc']['lyric'][:200] if len(data['romalrc']['lyric']) > 200 else data['romalrc']['lyric']
            print(f"   预览: {lyrics_preview}...")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'roman.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['romalrc']['lyric'])
        else:
            print("\n❌ 无罗马音歌词 (romalrc)")
        
        # 5. YRC格式歌词 (新版逐字歌词) ⭐重点
        if 'yrc' in data and 'lyric' in data['yrc'] and data['yrc']['lyric']:
            results['has_yrc'] = True
            print("\n✅ YRC逐字歌词 (yrc.lyric) - 新版格式 ⭐")
            print(f"   版本: {data['yrc'].get('version', 'N/A')}")
            lyrics_preview = data['yrc']['lyric'][:200] if len(data['yrc']['lyric']) > 200 else data['yrc']['lyric']
            print(f"   预览: {lyrics_preview}...")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'yrc_word_by_word.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['yrc']['lyric'])
        else:
            print("\n❌ 无YRC逐字歌词 (yrc)")
        
        # 6. YRC翻译
        if 'ytlrc' in data and 'lyric' in data['ytlrc'] and data['ytlrc']['lyric']:
            results['has_ytlrc'] = True
            print("\n✅ YRC翻译歌词 (ytlrc.lyric)")
            print(f"   版本: {data['ytlrc'].get('version', 'N/A')}")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'yrc_translation.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['ytlrc']['lyric'])
        else:
            print("\n❌ 无YRC翻译歌词 (ytlrc)")
        
        # 7. YRC罗马音
        if 'yromalrc' in data and 'lyric' in data['yromalrc'] and data['yromalrc']['lyric']:
            results['has_yromalrc'] = True
            print("\n✅ YRC罗马音歌词 (yromalrc.lyric)")
            print(f"   版本: {data['yromalrc'].get('version', 'N/A')}")
            if save_samples and output_dir:
                with open(os.path.join(output_dir, 'yrc_roman.lrc'), 'w', encoding='utf-8') as f:
                    f.write(data['yromalrc']['lyric'])
        else:
            print("\n❌ 无YRC罗马音歌词 (yromalrc)")
        
        # 完整JSON数据
        if save_samples and output_dir:
            with open(os.path.join(output_dir, 'full_response.json'), 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"\n💾 完整API响应已保存到: {output_dir}/full_response.json")
        
        print("\n" + "="*80)
        print("📈 汇总统计")
        print("="*80)
        print(f"普通LRC歌词:    {'✅' if results['has_lrc'] else '❌'}")
        print(f"逐字歌词(旧版):  {'✅' if results['has_klyric'] else '❌'}")
        print(f"YRC逐字歌词:     {'✅' if results['has_yrc'] else '❌'} ⭐推荐")
        print(f"翻译歌词:        {'✅' if results['has_tlyric'] else '❌'}")
        print(f"罗马音歌词:      {'✅' if results['has_romalrc'] else '❌'}")
        print(f"YRC翻译:         {'✅' if results['has_ytlrc'] else '❌'}")
        print(f"YRC罗马音:       {'✅' if results['has_yromalrc'] else '❌'}")
        print("="*80)
        
        return results


def analyze_ncm_file(ncm_path, save_samples=False):
    """分析NCM文件的歌词信息"""
    print(f"\n🎵 分析NCM文件: {os.path.basename(ncm_path)}")
    print("="*80)
    
    # 解析NCM文件
    ncm = NCMFile(ncm_path)
    if not ncm.decrypt():
        return False
    
    info = ncm.get_music_info()
    if not info:
        print("  ✗ 无法获取音乐信息")
        return False
    
    print(f"歌曲名称: {info['name']}")
    print(f"艺术家:   {info['artist']}")
    print(f"专辑:     {info['album']}")
    print(f"网易云ID: {info['id']}")
    
    # 获取歌词
    if not info['id']:
        print("  ✗ 未找到歌曲ID")
        return False
    
    print(f"\n🔍 正在查询歌词信息...")
    data = EnhancedLyricsChecker.get_all_lyrics_types(info['id'])
    
    if not data:
        return False
    
    # 创建输出目录
    output_dir = None
    if save_samples:
        output_dir = os.path.join(
            os.path.dirname(ncm_path),
            f"{info['name']} - {info['artist']} - Lyrics"
        )
        os.makedirs(output_dir, exist_ok=True)
        print(f"\n📁 样本文件保存目录: {output_dir}")
    
    # 分析歌词
    EnhancedLyricsChecker.analyze_lyrics(data, save_samples, output_dir)
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description='NCM增强歌词检查工具 - 分析是否有逐字歌词',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
示例:
  # 分析NCM文件的歌词类型
  python3 ncm_enhanced_lyrics_checker.py -f "music.ncm"
  
  # 分析并保存所有类型的歌词样本
  python3 ncm_enhanced_lyrics_checker.py -f "music.ncm" --save
  
  # 直接查询歌曲ID
  python3 ncm_enhanced_lyrics_checker.py --id 1234567890 --save
        '''
    )
    
    parser.add_argument('-f', '--file', help='NCM文件路径')
    parser.add_argument('--id', help='网易云音乐歌曲ID')
    parser.add_argument('--save', action='store_true', help='保存所有歌词样本到文件')
    
    args = parser.parse_args()
    
    # 检查依赖
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
        analyze_ncm_file(args.file, args.save)
    elif args.id:
        print(f"\n🔍 查询歌曲ID: {args.id}")
        data = EnhancedLyricsChecker.get_all_lyrics_types(args.id)
        if data:
            output_dir = None
            if args.save:
                output_dir = f"lyrics_{args.id}"
                os.makedirs(output_dir, exist_ok=True)
                print(f"\n📁 样本文件保存目录: {output_dir}")
            EnhancedLyricsChecker.analyze_lyrics(data, args.save, output_dir)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()

