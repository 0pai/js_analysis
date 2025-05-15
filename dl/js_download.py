#!/usr/bin/env python3

# MIT License
# Copyright (c) 2024 0pai
# See LICENSE file for details

import requests
import os
import sys
import time
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse
import re
import argparse

def sanitize_filename(filename):
    """ファイル名として使用できない文字を置換"""
    # Windowsで使用できない文字を置換
    return re.sub(r'[<>:"|?*]', '_', filename)

def create_directory_structure(url, base_dir):
    """URLから階層構造を維持したディレクトリパスを生成"""
    parsed_url = urlparse(url)
    
    # ドメイン名をディレクトリとして使用
    domain = parsed_url.netloc
    
    # パスから階層構造を取得
    path = parsed_url.path.strip('/')
    
    # パスをディレクトリとファイル名に分割
    if path:
        path_parts = path.split('/')
        if path_parts[-1].endswith('.js'):
            # 最後の要素がJSファイルの場合
            file_name = path_parts[-1]
            dir_parts = [domain] + path_parts[:-1]
        else:
            # JSファイルでない場合、index.jsとして保存
            file_name = 'index.js'
            dir_parts = [domain] + path_parts
    else:
        file_name = 'index.js'
        dir_parts = [domain]
    
    # ディレクトリパスを作成
    dir_path = os.path.join(base_dir, *[sanitize_filename(part) for part in dir_parts])
    
    # ファイル名をサニタイズ
    file_name = sanitize_filename(file_name)
    
    # クエリパラメータがある場合、ファイル名に追加
    if parsed_url.query:
        query_safe = re.sub(r'[^a-zA-Z0-9]', '_', parsed_url.query)[:50]  # 長すぎる場合は切り詰め
        base_name, ext = os.path.splitext(file_name)
        file_name = f"{base_name}_{query_safe}{ext}"
    
    return dir_path, file_name

def download_js(url, output_dir="./js_files", custom_headers=None):
    """JavaScriptファイルを階層構造を維持してダウンロード"""
    try:
        # ディレクトリとファイル名を生成
        dir_path, filename = create_directory_structure(url, output_dir)
        
        # ディレクトリが存在しない場合は作成
        os.makedirs(dir_path, exist_ok=True)
        
        # 完全なファイルパス
        filepath = os.path.join(dir_path, filename)
        
        # 既にファイルが存在する場合、スキップするか確認
        if os.path.exists(filepath):
            print(f"[SKIP] Already exists: {filepath}")
            return True, url
        
        # HTTPヘッダーを構築
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        }
        
        # カスタムヘッダーを追加
        if custom_headers:
            headers.update(custom_headers)
        
        # HTTPリクエストを送信
        response = requests.get(url, headers=headers, timeout=30, verify=False)
        response.raise_for_status()
        
        # ファイルを保存
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(response.text)
        
        # 相対パスで表示（見やすくするため）
        relative_path = os.path.relpath(filepath, output_dir)
        print(f"[SUCCESS] {url} -> {relative_path}")
        return True, url
        
    except requests.exceptions.Timeout:
        print(f"[TIMEOUT] {url}")
        return False, url
    except requests.exceptions.RequestException as e:
        print(f"[ERROR] {url}: {str(e)}")
        return False, url
    except Exception as e:
        print(f"[ERROR] {url}: Unexpected error: {str(e)}")
        return False, url

def parse_headers(header_str):
    """ヘッダー文字列をパース"""
    headers = {}
    if not header_str:
        return headers
    
    # 複数のヘッダーをセミコロンまたはカンマで区切る
    header_pairs = re.split(r'[;,]', header_str)
    
    for pair in header_pairs:
        pair = pair.strip()
        if ':' in pair:
            key, value = pair.split(':', 1)
            headers[key.strip()] = value.strip()
    
    return headers

def load_headers_from_file(filename):
    """ファイルからヘッダーを読み込む"""
    headers = {}
    try:
        with open(filename, 'r') as f:
            # JSON形式の場合
            try:
                headers = json.load(f)
            except json.JSONDecodeError:
                # Key: Value 形式の場合
                f.seek(0)
                for line in f:
                    line = line.strip()
                    if line and ':' in line:
                        key, value = line.split(':', 1)
                        headers[key.strip()] = value.strip()
    except FileNotFoundError:
        print(f"Warning: Header file '{filename}' not found")
    
    return headers

def main():
    parser = argparse.ArgumentParser(
        description='Download JavaScript files while maintaining directory structure',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic usage
  python js_downloader.py urls.txt

  # With custom header
  python js_downloader.py urls.txt -H "X-Bug-Bounty: hunter123"

  # With multiple headers
  python js_downloader.py urls.txt -H "X-Bug-Bounty: hunter123" -H "Authorization: Bearer token123"

  # Headers from file (JSON format)
  python js_downloader.py urls.txt --header-file headers.json

  # Headers from file (Key: Value format)
  python js_downloader.py urls.txt --header-file headers.txt

Header file formats:
  JSON format (headers.json):
    {
      "X-Bug-Bounty": "hunter123",
      "Authorization": "Bearer token123"
    }

  Text format (headers.txt):
    X-Bug-Bounty: hunter123
    Authorization: Bearer token123
        """
    )
    
    parser.add_argument('url_file', help='File containing JavaScript URLs (one per line)')
    parser.add_argument('-o', '--output', dest='output_dir', default='./js_files', 
                        help='Output directory (default: ./js_files)')
    parser.add_argument('-H', '--header', action='append', dest='headers',
                        help='Add custom header (format: "Key: Value"). Can be used multiple times.')
    parser.add_argument('--header-file', help='Load headers from file (JSON or Key:Value format)')
    parser.add_argument('-t', '--threads', type=int, default=10, help='Number of concurrent downloads (default: 10)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output (show headers being used)')
    
    args = parser.parse_args()
    
    # ヘッダーを収集
    custom_headers = {}
    
    # コマンドラインからのヘッダー
    if args.headers:
        for header in args.headers:
            if ':' in header:
                key, value = header.split(':', 1)
                custom_headers[key.strip()] = value.strip()
    
    # ファイルからのヘッダー
    if args.header_file:
        file_headers = load_headers_from_file(args.header_file)
        custom_headers.update(file_headers)
    
    # Verboseモード：使用するヘッダーを表示
    if args.verbose and custom_headers:
        print("Using custom headers:")
        for key, value in custom_headers.items():
            # 機密情報の一部をマスク
            if any(sensitive in key.lower() for sensitive in ['authorization', 'token', 'key', 'secret']):
                masked_value = value[:5] + '*' * (len(value) - 5) if len(value) > 5 else '*' * len(value)
                print(f"  {key}: {masked_value}")
            else:
                print(f"  {key}: {value}")
        print()
    
    # URLリストを読み込む
    try:
        with open(args.url_file, 'r') as f:
            urls = [line.strip() for line in f if line.strip()]
    except FileNotFoundError:
        print(f"Error: File '{args.url_file}' not found")
        sys.exit(1)
    
    output_dir = args.output_dir
    
    print(f"Found {len(urls)} JavaScript URLs to download")
    print(f"Output directory: {output_dir}")
    print(f"Concurrent downloads: {args.threads}")
    if custom_headers:
        print(f"Using {len(custom_headers)} custom header(s)")
    print(f"Maintaining directory structure based on URL paths\n")
    
    # 重複URLを削除
    unique_urls = list(set(urls))
    if len(unique_urls) < len(urls):
        print(f"Removed {len(urls) - len(unique_urls)} duplicate URLs")
        urls = unique_urls
    
    # 並列ダウンロード
    successful = 0
    failed = 0
    failed_urls = []
    
    with ThreadPoolExecutor(max_workers=args.threads) as executor:
        futures = {executor.submit(download_js, url, output_dir, custom_headers): url for url in urls}
        
        for future in as_completed(futures):
            success, url = future.result()
            if success:
                successful += 1
            else:
                failed += 1
                failed_urls.append(url)
            
            # 進捗表示
            total = successful + failed
            print(f"Progress: {total}/{len(urls)} (Success: {successful}, Failed: {failed})", end='\r')
    
    print(f"\n\nDownload completed: {successful} success, {failed} failed")
    
    # 失敗したURLをファイルに保存
    if failed_urls:
        with open('failed_urls.txt', 'w') as f:
            for url in failed_urls:
                f.write(f"{url}\n")
        print("Failed URLs saved to failed_urls.txt")
    
    # ダウンロードしたファイルの統計情報を表示
    print("\nDirectory structure created:")
    total_size = 0
    file_count = 0
    
    for root, dirs, files in os.walk(output_dir):
        level = root.replace(output_dir, '').count(os.sep)
        indent = ' ' * 2 * level
        relative_root = os.path.relpath(root, output_dir)
        if relative_root != '.':
            print(f"{indent}{os.path.basename(root)}/")
        
        # ファイルサイズの合計を計算
        subindent = ' ' * 2 * (level + 1)
        for file in files:
            if file.endswith('.js'):
                file_path = os.path.join(root, file)
                file_size = os.path.getsize(file_path)
                total_size += file_size
                file_count += 1
                # 最初の5階層まで表示
                if level < 5:
                    print(f"{subindent}{file} ({file_size:,} bytes)")
    
    print(f"\nTotal: {file_count} files, {total_size:,} bytes ({total_size/1024/1024:.2f} MB)")

if __name__ == "__main__":
    # SSL証明書の警告を無効化（開発環境用）
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    main()
