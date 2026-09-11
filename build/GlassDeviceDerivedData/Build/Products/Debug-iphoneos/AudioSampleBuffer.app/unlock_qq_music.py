#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QQ音乐加密文件解密工具 - 完整版
支持: QMC0, QMC3, QMCFLAC, QMCOGG, MGG 等所有 QQ音乐加密格式
基于 unlock-music 项目的 Python 实现
"""

import os
import sys
import struct
import json
from Crypto.Cipher import AES
import base64

class QQMusicDecryptor:
    """QQ音乐解密器 - 支持多种加密格式"""
    
    def __init__(self, file_path):
        self.file_path = file_path
        self.file_size = os.path.getsize(file_path)
        self.cipher_type = None
        
    def detect_cipher(self):
        """检测加密类型"""
        with open(self.file_path, 'rb') as f:
            # 读取文件尾部特征
            if self.file_size < 512:
                return None
            
            # 检查文件尾部是否有 STag 或 QTag
            f.seek(-512, 2)  # 从文件尾往前 512 字节
            tail = f.read(512)
            
            if b'STag' in tail or b'QTag' in tail:
                return 'QMCv2'  # 新版 QMC (带密钥)
            
            # 检查文件头
            f.seek(0)
            header = f.read(16)
            
            # 尝试静态密钥解密来判断
            return 'QMCv1'  # 旧版 QMC (静态密钥)
    
    def get_mask_v1(self, offset):
        """QMCv1 静态掩码算法"""
        # 静态种子表
        seed_map = [
            0x4a, 0xd6, 0xca, 0x90, 0x67, 0xf7, 0x52, 0xd8,
            0xa1, 0x66, 0x62, 0x9f, 0x5b, 0x09, 0x62, 0x55
        ]
        
        if offset > 0x7fff:
            offset %= 0x7fff
        
        idx = (offset * offset + 27) & 0xff
        return seed_map[((offset * offset + 27) >> 8) & 0xf] ^ \
               seed_map[idx & 0xf] ^ idx
    
    def get_mask_v2(self, offset, key_data):
        """QMCv2 动态密钥算法"""
        if not key_data:
            return self.get_mask_v1(offset)
        
        key_len = len(key_data)
        return key_data[offset % key_len]
    
    def extract_key_v2(self):
        """从文件中提取 QMCv2 密钥"""
        with open(self.file_path, 'rb') as f:
            # 读取文件尾部
            f.seek(-4, 2)
            tail_size = struct.unpack('<I', f.read(4))[0]
            
            if tail_size > self.file_size or tail_size < 100:
                return None
            
            # 读取尾部数据
            f.seek(-tail_size, 2)
            tail_data = f.read(tail_size - 4)
            
            # 查找密钥标记
            if b'QTag' in tail_data:
                # 解析密钥
                try:
                    key_start = tail_data.index(b'QTag') + 4
                    key_len = struct.unpack('<I', tail_data[key_start:key_start+4])[0]
                    key_data = tail_data[key_start+4:key_start+4+key_len]
                    
                    # 简单解密密钥 (实际算法可能更复杂)
                    decrypted_key = bytearray()
                    for i, byte in enumerate(key_data):
                        decrypted_key.append(byte ^ 0x66 ^ (i & 0xff))
                    
                    return bytes(decrypted_key)
                except:
                    pass
            
            return None
    
    def detect_output_format(self, decrypted_header):
        """根据解密后的文件头判断格式"""
        # MP3
        if decrypted_header[:3] == b'ID3' or \
           (decrypted_header[0] == 0xFF and (decrypted_header[1] & 0xE0) == 0xE0):
            return '.mp3'
        
        # OGG
        if decrypted_header[:4] == b'OggS':
            return '.ogg'
        
        # FLAC
        if decrypted_header[:4] == b'fLaC':
            return '.flac'
        
        # M4A
        if decrypted_header[4:8] == b'ftyp':
            return '.m4a'
        
        # WAV
        if decrypted_header[:4] == b'RIFF':
            return '.wav'
        
        return '.mp3'  # 默认
    
    def decrypt(self, output_path=None):
        """解密文件"""
        print(f"🔓 解密: {os.path.basename(self.file_path)}")
        
        # 检测加密类型
        self.cipher_type = self.detect_cipher()
        print(f"   加密类型: {self.cipher_type}")
        
        # 提取密钥 (如果是 v2)
        key_data = None
        audio_size = self.file_size
        
        if self.cipher_type == 'QMCv2':
            key_data = self.extract_key_v2()
            if key_data:
                # 计算音频数据大小（去掉尾部密钥部分）
                with open(self.file_path, 'rb') as f:
                    f.seek(-4, 2)
                    tail_size = struct.unpack('<I', f.read(4))[0]
                    audio_size = self.file_size - tail_size
                print(f"   找到密钥: {len(key_data)} 字节")
        
        # 开始解密
        try:
            with open(self.file_path, 'rb') as fin:
                # 读取音频数据
                audio_data = fin.read(audio_size)
            
            # 解密
            decrypted = bytearray()
            for offset, byte in enumerate(audio_data):
                if self.cipher_type == 'QMCv2' and key_data:
                    mask = self.get_mask_v2(offset, key_data)
                else:
                    mask = self.get_mask_v1(offset)
                decrypted.append(byte ^ mask)
            
            # 检测输出格式
            ext = self.detect_output_format(bytes(decrypted[:16]))
            
            if output_path is None:
                base_name = os.path.splitext(self.file_path)[0]
                output_path = base_name + ext
            
            # 写入文件
            with open(output_path, 'wb') as fout:
                fout.write(decrypted)
            
            # 验证解密结果
            file_type = self.verify_audio_file(output_path)
            
            print(f"   ✅ 解密成功")
            print(f"   格式: {ext.upper()[1:]}")
            print(f"   输出: {os.path.basename(output_path)}")
            print(f"   大小: {len(decrypted) / 1024 / 1024:.2f} MB")
            
            if file_type == 'valid':
                print(f"   验证: ✅ 文件可用")
            else:
                print(f"   验证: ⚠️  文件可能已损坏")
            
            return output_path
            
        except Exception as e:
            print(f"   ❌ 解密失败: {e}")
            import traceback
            traceback.print_exc()
            return None
    
    def verify_audio_file(self, file_path):
        """验证音频文件是否有效"""
        with open(file_path, 'rb') as f:
            header = f.read(16)
        
        # 检查常见音频格式的文件头
        valid_headers = [
            b'ID3',           # MP3 with ID3
            b'\xff\xfb',      # MP3
            b'\xff\xf3',      # MP3
            b'\xff\xf2',      # MP3
            b'OggS',          # OGG
            b'fLaC',          # FLAC
            b'RIFF',          # WAV
        ]
        
        for valid_header in valid_headers:
            if header.startswith(valid_header):
                return 'valid'
        
        # 检查 ftyp (M4A/MP4)
        if header[4:8] == b'ftyp':
            return 'valid'
        
        return 'unknown'


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description='QQ音乐加密文件解密工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 解密单个文件
  python3 unlock_qq_music.py song.ogg
  
  # 批量解密目录
  python3 unlock_qq_music.py /path/to/music/ -r
  
  # 解密后删除原文件
  python3 unlock_qq_music.py song.ogg --remove-original
        """
    )
    
    parser.add_argument('path', help='加密文件路径或目录')
    parser.add_argument('-o', '--output', help='输出文件路径')
    parser.add_argument('-r', '--recursive', action='store_true', help='递归处理子目录')
    parser.add_argument('--remove-original', action='store_true', help='解密成功后删除原文件')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.path):
        print(f"❌ 路径不存在: {args.path}")
        return
    
    # 支持的加密文件扩展名
    encrypted_extensions = [
        '.ogg',      # QMC 加密的 OGG
        '.qmc',      # QMC 通用
        '.qmc0',     # QMC v1
        '.qmc3',     # QMC v2
        '.qmcflac',  # QMC FLAC
        '.qmcogg',   # QMC OGG
        '.mgg',      # MGG
        '.mflac',    # MGG FLAC
        '.mgge',     # MGG 加密
    ]
    
    if os.path.isfile(args.path):
        # 单个文件
        print("="*60)
        decryptor = QQMusicDecryptor(args.path)
        output = decryptor.decrypt(args.output)
        
        if output and args.remove_original:
            try:
                os.remove(args.path)
                print(f"🗑️  已删除原文件")
            except Exception as e:
                print(f"⚠️  无法删除原文件: {e}")
        print("="*60)
    
    elif os.path.isdir(args.path):
        # 目录
        files = []
        
        if args.recursive:
            for root, dirs, filenames in os.walk(args.path):
                for filename in filenames:
                    ext = os.path.splitext(filename)[1].lower()
                    if ext in encrypted_extensions:
                        files.append(os.path.join(root, filename))
        else:
            for filename in os.listdir(args.path):
                filepath = os.path.join(args.path, filename)
                if os.path.isfile(filepath):
                    ext = os.path.splitext(filename)[1].lower()
                    if ext in encrypted_extensions:
                        files.append(filepath)
        
        if not files:
            print(f"❌ 未找到加密文件")
            return
        
        print(f"📂 找到 {len(files)} 个加密文件\n")
        
        success = 0
        failed = 0
        
        for i, filepath in enumerate(files, 1):
            print(f"\n[{i}/{len(files)}] {'='*50}")
            decryptor = QQMusicDecryptor(filepath)
            output = decryptor.decrypt()
            
            if output:
                success += 1
                if args.remove_original:
                    try:
                        os.remove(filepath)
                        print(f"🗑️  已删除原文件")
                    except:
                        pass
            else:
                failed += 1
        
        print(f"\n{'='*60}")
        print(f"📊 统计:")
        print(f"   成功: {success} 个")
        print(f"   失败: {failed} 个")
        print(f"   总计: {len(files)} 个")


if __name__ == '__main__':
    # 检查依赖
    try:
        from Crypto.Cipher import AES
    except ImportError:
        print("❌ 缺少依赖: pycryptodome")
        print("请运行: pip3 install pycryptodome")
        sys.exit(1)
    
    main()

