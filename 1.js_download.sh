#!/bin/bash

# MIT License
# Copyright (c) 2024 0pai
# See LICENSE file for details

# JSファイル収集・解析パイプライン
# Bug Bounty向けJavaScript解析フレームワーク

# ヘルプ表示関数
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN       Target domain (required if not using -u)"
    echo "  -u, --url-file FILE       File containing JavaScript URLs (skips getJS step)"
    echo "  -H, --header HEADER       Custom header for downloads (can be used multiple times)"
    echo "  -t, --threads NUM         Number of download threads (default: 10)"
    echo "  -p, --protocol PROTOCOL   Protocol to use: http, https, or both (default: https)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Basic usage with domain (HTTPS)"
    echo "  $0 -d example.com"
    echo ""
    echo "  # Use HTTP instead of HTTPS"
    echo "  $0 -d example.com -p http"
    echo ""
    echo "  # Try both HTTP and HTTPS"
    echo "  $0 -d example.com -p both"
    echo ""
    echo "  # With custom headers"
    echo "  $0 -d example.com -H \"X-Bug-Bounty: hunter123\" -H \"Authorization: Bearer token\""
    echo ""
    echo "  # Using existing URL file"
    echo "  $0 -u js_urls.txt -H \"X-Bug-Bounty: hunter123\""
    exit 0
}

# デフォルト値
TARGET_DOMAIN=""
URL_FILE=""
OUTPUT_DIR="./js_analysis"
HEADERS=()
THREADS=10
PROTOCOL="https"

# 引数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            TARGET_DOMAIN="$2"
            shift 2
            ;;
        -u|--url-file)
            URL_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -H|--header)
            HEADERS+=("-H" "$2")
            shift 2
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        -p|--protocol)
            PROTOCOL="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# プロトコルの検証
if [[ "$PROTOCOL" != "http" ]] && [[ "$PROTOCOL" != "https" ]] && [[ "$PROTOCOL" != "both" ]]; then
    echo "Error: Invalid protocol. Must be 'http', 'https', or 'both'"
    exit 1
fi

# 入力検証
if [[ -z "$TARGET_DOMAIN" ]] && [[ -z "$URL_FILE" ]]; then
    echo "Error: Either domain (-d) or URL file (-u) must be specified"
    echo "Use -h or --help for usage information"
    exit 1
fi

# ディレクトリ設定
JS_DIR="$OUTPUT_DIR/js_files"
#ANALYSIS_DIR="$OUTPUT_DIR/analysis"

# ディレクトリ作成
mkdir -p "$JS_DIR"

echo "JavaScript Analysis Pipeline"
echo "==========================="
if [[ -n "$TARGET_DOMAIN" ]]; then
    echo "Target domain: $TARGET_DOMAIN"
    echo "Protocol: $PROTOCOL"
fi
if [[ -n "$URL_FILE" ]]; then
    echo "URL file: $URL_FILE"
fi
echo "Output directory: $OUTPUT_DIR"
echo "JS directory: $JS_DIR"
echo "Analysis directory: $ANALYSIS_DIR"
echo "Download threads: $THREADS"
if [[ ${#HEADERS[@]} -gt 0 ]]; then
    echo "Custom headers: ${#HEADERS[@]} header(s) configured"
fi
echo ""

# 1. JavaScriptファイルの収集（URL_FILEが指定されていない場合のみ）
if [[ -z "$URL_FILE" ]]; then
    echo "[+] Collecting JavaScript files with getJS..."
    if ! command -v getJS &> /dev/null; then
        echo "Error: getJS is not installed"
        echo "Install it from: https://github.com/003random/getJS"
        exit 1
    fi
    
    # 一時ファイルを作成
    TEMP_URLS="$OUTPUT_DIR/js_urls_temp.txt"
    > "$TEMP_URLS"
    
    # プロトコルに基づいてURLを収集
    if [[ "$PROTOCOL" == "https" ]] || [[ "$PROTOCOL" == "both" ]]; then
        echo "  - Collecting from HTTPS..."
        getJS --complete --resolve --url "https://$TARGET_DOMAIN" >> "$TEMP_URLS"
    fi
    
    if [[ "$PROTOCOL" == "http" ]] || [[ "$PROTOCOL" == "both" ]]; then
        echo "  - Collecting from HTTP..."
        getJS --complete --resolve --url "http://$TARGET_DOMAIN" >> "$TEMP_URLS"
    fi
    
    # 結果をマージして重複を削除
    sort -u "$TEMP_URLS" > "$OUTPUT_DIR/js_urls_unique.txt"
    URL_FILE="$OUTPUT_DIR/js_urls_unique.txt"
    rm -f "$TEMP_URLS"
    
    echo "Found $(wc -l < "$URL_FILE") unique JavaScript URLs"
else
    echo "[+] Using provided URL file: $URL_FILE"
    if [[ ! -f "$URL_FILE" ]]; then
        echo "Error: URL file not found: $URL_FILE"
        exit 1
    fi
fi

# 2. JavaScriptファイルのダウンロード（js_download.pyを使用）
echo "[+] Downloading JavaScript files..."

# js_download.pyの存在確認
JS_DOWNLOADER="dl/js_download.py"
if [[ ! -f "$JS_DOWNLOADER" ]]; then
    # スクリプトが同じディレクトリにない場合、パスを調整
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    JS_DOWNLOADER="$SCRIPT_DIR/js_download.py"
    
    if [[ ! -f "$JS_DOWNLOADER" ]]; then
        echo "Error: js_download.py not found"
        echo "Please ensure js_download.py is in the same directory as this script"
        exit 1
    fi
fi

# Python3の確認
if ! command -v python3 &> /dev/null; then
    echo "Error: Python3 is not installed"
    exit 1
fi

# js_download.pyを実行
echo "Executing: python3 $JS_DOWNLOADER $URL_FILE -o $JS_DIR -t $THREADS ${HEADERS[@]}"
python3 "$JS_DOWNLOADER" "$URL_FILE" -o "$JS_DIR" -t "$THREADS" "${HEADERS[@]}"

if [[ $? -ne 0 ]]; then
    echo "Error: Download failed"
    exit 1
fi