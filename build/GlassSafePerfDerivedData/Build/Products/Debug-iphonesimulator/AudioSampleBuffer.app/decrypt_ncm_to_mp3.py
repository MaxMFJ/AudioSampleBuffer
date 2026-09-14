#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NCM 文件解密并转换为 MP3
完整的解密和转换工具
"""

import struct
import binascii
import base64
import json
import os
import sys
from Crypto.Cipher import AES

class NCMDecryptor:
    """NCM 文件解密器"""
    
    CORE_KEY = binascii.a2b_hex("687A4852416D736F356B496E62617857")
    META_KEY = binascii.a2b_hex("2331346C6A6B5F215C5D2630553C2728")
    
    def __init__(self, filepath):
        self.filepath = filepath
        self.metadata = None
        self.key_box = None
        
    def decrypt(self, output_path=None):
        """完整解密流程"""
        print(f"🔓 解密: {os.path.basename(self.filepath)}")
        
        try:
            with open(self.filepath, 'rb') as f:
                # 1. 检查文件头
                header = f.read(8)
                if header != b'CTENFDAM':
                    print(f"   ❌ 不是有效的 NCM 文件")
                    return None
                
                f.seek(2, 1)  # 跳过2字节
                
                # 2. 读取和解密密钥
                key_length = struct.unpack('<I', f.read(4))[0]
                key_data = bytearray(f.read(key_length))
                
                for i in range(len(key_data)):
                    key_data[i] ^= 0x64
                
                # AES 解密密钥
                cipher = AES.new(self.CORE_KEY, AES.MODE_ECB)
                key_data = cipher.decrypt(bytes(key_data))
                key_data = key_data[17:]  # 去掉 "neteasecloudmusic"
                
                # 生成密钥盒
                self.key_box = bytearray(range(256))
                key_len = len(key_data)
                
                j = 0
                for i in range(256):
                    j = (j + self.key_box[i] + key_data[i % key_len]) & 0xff
                    self.key_box[i], self.key_box[j] = self.key_box[j], self.key_box[i]
                
                # 3. 读取元数据
                meta_length = struct.unpack('<I', f.read(4))[0]
                if meta_length > 0:
                    meta_data = bytearray(f.read(meta_length))
                    
                    for i in range(len(meta_data)):
                        meta_data[i] ^= 0x63
                    
                    # Base64 解码
                    meta_data = base64.b64decode(meta_data[22:])
                    
                    # AES 解密
                    cipher = AES.new(self.META_KEY, AES.MODE_ECB)
                    meta_data = cipher.decrypt(meta_data)
                    
                    # 去除 PKCS7 填充
                    meta_data = meta_data[:-meta_data[-1]]
                    
                    # 解析 JSON
                    meta_json = meta_data.decode('utf-8')
                    meta_json = meta_json[6:]  # 去除 "music:" 前缀
                    self.metadata = json.loads(meta_json)
                    
                    print(f"   歌曲: {self.metadata.get('musicName', '未知')}")
                    print(f"   艺术家: {', '.join([a[0] for a in self.metadata.get('artist', [])])}")
                
                # 4. 跳过 CRC 和封面
                f.seek(5, 1)  # 跳过 CRC
                
                image_size = struct.unpack('<I', f.read(4))[0]
                f.seek(image_size, 1)  # 跳过封面
                
                # 5. 解密音频数据
                audio_data = f.read()
                decrypted = bytearray()
                
                for i, byte in enumerate(audio_data):
                    j = (i + 1) & 0xff
                    k = self.key_box[(self.key_box[j] + self.key_box[(self.key_box[j] + j) & 0xff]) & 0xff]
                    decrypted.append(byte ^ k)
                
                # 6. 确定输出格式
                if output_path is None:
                    # 根据元数据或文件头判断格式
                    format_ext = '.mp3'  # 默认
                    
                    if self.metadata:
                        format_type = self.metadata.get('format', 'mp3')
                        format_ext = f'.{format_type}'
                    elif decrypted[:4] == b'fLaC':
                        format_ext = '.flac'
                    
                    base_name = os.path.splitext(self.filepath)[0]
                    output_path = base_name + format_ext
                
                # 7. 写入文件
                with open(output_path, 'wb') as fout:
                    fout.write(decrypted)
                
                print(f"   ✅ 解密成功")
                print(f"   格式: {output_path.split('.')[-1].upper()}")
                print(f"   输出: {os.path.basename(output_path)}")
                print(f"   大小: {len(decrypted) / 1024 / 1024:.2f} MB")
                
                return output_path
                
        except Exception as e:
            print(f"   ❌ 解密失败: {e}")
            import traceback
            traceback.print_exc()
            return None


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description='NCM 文件解密工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 解密单个文件
  python3 decrypt_ncm_to_mp3.py song.ncm
  
  # 批量解密目录
  python3 decrypt_ncm_to_mp3.py /path/to/music/ -r
  
  # 解密后删除原文件
  python3 decrypt_ncm_to_mp3.py song.ncm --remove
        """
    )
    
    parser.add_argument('path', help='NCM 文件路径或目录')
    parser.add_argument('-o', '--output', help='输出文件路径')
    parser.add_argument('-r', '--recursive', action='store_true', help='递归处理子目录')
    parser.add_argument('--remove', action='store_true', help='解密成功后删除原文件')
    parser.add_argument('--copy-to', help='解密后复制到指定目录')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.path):
        print(f"❌ 路径不存在: {args.path}")
        return
    
    if os.path.isfile(args.path):
        # 单个文件
        print("="*60)
        decryptor = NCMDecryptor(args.path)
        output = decryptor.decrypt(args.output)
        
        if output:
            if args.copy_to:
                import shutil
                dest = os.path.join(args.copy_to, os.path.basename(output))
                shutil.copy2(output, dest)
                print(f"   📋 已复制到: {dest}")
            
            if args.remove:
                try:
                    os.remove(args.path)
                    print(f"   🗑️  已删除原文件")
                except Exception as e:
                    print(f"   ⚠️  无法删除原文件: {e}")
        print("="*60)
    
    elif os.path.isdir(args.path):
        # 目录
        files = []
        
        if args.recursive:
            for root, dirs, filenames in os.walk(args.path):
                for filename in filenames:
                    if filename.lower().endswith('.ncm'):
                        files.append(os.path.join(root, filename))
        else:
            for filename in os.listdir(args.path):
                filepath = os.path.join(args.path, filename)
                if os.path.isfile(filepath) and filename.lower().endswith('.ncm'):
                    files.append(filepath)
        
        if not files:
            print(f"❌ 未找到 NCM 文件")
            return
        
        print(f"📂 找到 {len(files)} 个 NCM 文件\n")
        
        success = 0
        failed = 0
        
        for i, filepath in enumerate(files, 1):
            print(f"\n[{i}/{len(files)}] {'='*50}")
            decryptor = NCMDecryptor(filepath)
            output = decryptor.decrypt()
            
            if output:
                success += 1
                
                if args.copy_to:
                    import shutil
                    dest = os.path.join(args.copy_to, os.path.basename(output))
                    shutil.copy2(output, dest)
                    print(f"   📋 已复制到: {dest}")
                
                if args.remove:
                    try:
                        os.remove(filepath)
                        print(f"   🗑️  已删除原文件")
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

