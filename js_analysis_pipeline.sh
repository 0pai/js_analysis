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
    echo "  -o, --output DIR          Output directory (default: ./js_analysis)"
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
    echo ""
    echo "  # Custom output directory and threads"
    echo "  $0 -d example.com -o ./custom_output -t 5"
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
ANALYSIS_DIR="$OUTPUT_DIR/analysis"

# ディレクトリ作成
mkdir -p "$JS_DIR" "$ANALYSIS_DIR"

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

# 3. 基本的な解析
echo ""
echo "[+] Analyzing JavaScript files..."

# 機密情報の検索
echo "[+] Searching for secrets..."
grep -rHn -E "(api[_-]?key|api[_-]?secret|auth[_-]?token|password|passwd|pwd|credential|private[_-]?key)" "$JS_DIR" | grep -v "node_modules" > "$ANALYSIS_DIR/potential_secrets.txt" 2>/dev/null || true

# エンドポイントの抽出
echo "[+] Extracting endpoints..."
grep -rHno -E "(https?:)?//[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/[^\"' ]*)?|/api/[^\"' ]*" "$JS_DIR" | sort -u > "$ANALYSIS_DIR/endpoints.txt" 2>/dev/null || true

# 関数名の抽出
echo "[+] Extracting function names..."
grep -rHno -E "function\s+([a-zA-Z_$][a-zA-Z0-9_$]*)" "$JS_DIR" | sed 's/.*function\s\+//' > "$ANALYSIS_DIR/functions.txt" 2>/dev/null || true

# AWSキーパターンの検索
echo "[+] Searching for AWS keys..."
grep -rHn -E "AKIA[0-9A-Z]{16}" "$JS_DIR" > "$ANALYSIS_DIR/aws_keys.txt" 2>/dev/null || true

# JWTトークンの検索
echo "[+] Searching for JWT tokens..."
grep -rHno -E "eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*" "$JS_DIR" > "$ANALYSIS_DIR/jwt_tokens.txt" 2>/dev/null || true

# 4. 高度な解析ツールの実行（利用可能な場合）
echo "[+] Running advanced analysis tools..."

# LinkFinderを使用してリンクを抽出
if command -v linkfinder &> /dev/null || command -v LinkFinder.py &> /dev/null; then
    echo "  - Running LinkFinder..."
    for file in "$JS_DIR"/*.js; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")
            echo "    Processing: $filename"
            if command -v linkfinder &> /dev/null; then
                linkfinder -i "$file" -o cli >> "$ANALYSIS_DIR/linkfinder_results.txt" 2>/dev/null || true
            else
                LinkFinder.py -i "$file" -o cli >> "$ANALYSIS_DIR/linkfinder_results.txt" 2>/dev/null || true
            fi
        fi
    done
else
    echo "  - LinkFinder not found (skipping)"
fi

# JSParserを使用
if command -v jsparser &> /dev/null; then
    echo "  - Running JSParser..."
    for file in "$JS_DIR"/*.js; do
        if [[ -f "$file" ]]; then
            jsparser -f "$file" >> "$ANALYSIS_DIR/jsparser_results.txt" 2>/dev/null || true
        fi
    done
else
    echo "  - JSParser not found (skipping)"
fi

# 5. 結果のサマリー
echo ""
echo "[+] Creating summary..."

# 各ファイルの行数をカウント
function count_lines() {
    if [[ -f "$1" ]]; then
        wc -l < "$1"
    else
        echo "0"
    fi
}

# サマリーファイルの作成
cat > "$ANALYSIS_DIR/summary.txt" <<EOF
JavaScript Analysis Summary
==========================
Analysis Date: $(date)
Target: ${TARGET_DOMAIN:-"URLs from $URL_FILE"}
Protocol: ${PROTOCOL}
Total JS files: $(find "$JS_DIR" -name "*.js" -type f | wc -l)

Security Findings:
- Potential secrets found: $(count_lines "$ANALYSIS_DIR/potential_secrets.txt")
- AWS keys found: $(count_lines "$ANALYSIS_DIR/aws_keys.txt")
- JWT tokens found: $(count_lines "$ANALYSIS_DIR/jwt_tokens.txt")

Extracted Data:
- Unique endpoints found: $(count_lines "$ANALYSIS_DIR/endpoints.txt")
- Functions identified: $(count_lines "$ANALYSIS_DIR/functions.txt")
- LinkFinder results: $(count_lines "$ANALYSIS_DIR/linkfinder_results.txt")
- JSParser results: $(count_lines "$ANALYSIS_DIR/jsparser_results.txt")

Files:
- Secrets: $ANALYSIS_DIR/potential_secrets.txt
- AWS Keys: $ANALYSIS_DIR/aws_keys.txt
- JWT Tokens: $ANALYSIS_DIR/jwt_tokens.txt
- Endpoints: $ANALYSIS_DIR/endpoints.txt
- Functions: $ANALYSIS_DIR/functions.txt
- LinkFinder: $ANALYSIS_DIR/linkfinder_results.txt
- JSParser: $ANALYSIS_DIR/jsparser_results.txt

Download Configuration:
- Threads used: $THREADS
- Custom headers: ${#HEADERS[@]}
EOF

# 6. 最終レポート表示
echo ""
echo "============================================"
echo "Analysis Complete!"
echo "============================================"
cat "$ANALYSIS_DIR/summary.txt"
echo ""
echo "For detailed results, check the files in:"
echo "  $ANALYSIS_DIR"
echo ""

# 重要な発見がある場合は強調表示
if [[ $(count_lines "$ANALYSIS_DIR/potential_secrets.txt") -gt 0 ]]; then
    echo "⚠️  ATTENTION: Potential secrets found! Check $ANALYSIS_DIR/potential_secrets.txt"
fi
if [[ $(count_lines "$ANALYSIS_DIR/aws_keys.txt") -gt 0 ]]; then
    echo "⚠️  ATTENTION: AWS keys found! Check $ANALYSIS_DIR/aws_keys.txt"
fi
if [[ $(count_lines "$ANALYSIS_DIR/jwt_tokens.txt") -gt 0 ]]; then
    echo "⚠️  ATTENTION: JWT tokens found! Check $ANALYSIS_DIR/jwt_tokens.txt"
fi
