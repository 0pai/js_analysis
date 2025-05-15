# JS Analysis - JavaScript セキュリティ解析ツールキット

バグバウンティハンターやセキュリティ研究者向けの、JavaScriptファイルからセキュリティ脆弱性、隠されたエンドポイント、機密情報を分析する包括的なツールキットです。

## 🌟 機能

- **一括JavaScriptダウンロード**: ディレクトリ構造を維持しながらJavaScriptファイルをダウンロード
- **自動解析**: 機密情報、エンドポイント、潜在的なセキュリティ問題を抽出
- **カスタムヘッダーサポート**: プライベートプログラム用の認証ヘッダーを追加
- **プロトコルの柔軟性**: HTTPとHTTPSの両方をサポート
- **高度な解析ツール統合**: LinkFinder、JSParserサポート
- **詳細なレポート**: 検出結果の包括的なサマリー

## 🚀 クイックスタート

### 前提条件

- Python 3.6+
- Bash
- [getJS](https://github.com/003random/getJS) (自動JS検出用)
- オプション: [LinkFinder](https://github.com/GerbenJavado/LinkFinder), [JSParser](https://github.com/nahamsec/JSParser)

### インストール

```bash
git clone https://github.com/0pai/js_analysis.git
cd js_analysis
chmod +x js_analysis_pipeline.sh
```

### 基本的な使い方

```bash
# ドメインを解析
./js_analysis_pipeline.sh -d example.com

# カスタムヘッダー付き（バグバウンティプログラム用）
./js_analysis_pipeline.sh -d example.com -H "X-Bug-Bounty: hunter123"

# HTTPSの代わりにHTTPを使用
./js_analysis_pipeline.sh -d example.com -p http

# 既存のURLリストを使用
./js_analysis_pipeline.sh -u js_urls.txt
```

## 📖 詳細ドキュメント

### js_analysis_pipeline.sh

全体のプロセスを統括するメインの解析パイプラインです。

#### オプション

- `-d, --domain DOMAIN`: ターゲットドメイン（-uを使用しない場合は必須）
- `-u, --url-file FILE`: JavaScriptのURLを含むファイル（getJSステップをスキップ）
- `-o, --output DIR`: 出力ディレクトリ（デフォルト: ./js_analysis）
- `-H, --header HEADER`: ダウンロード用のカスタムヘッダー（複数回使用可）
- `-t, --threads NUM`: ダウンロードスレッド数（デフォルト: 10）
- `-p, --protocol PROTOCOL`: 使用するプロトコル: http、https、または both（デフォルト: https）
- `-h, --help`: ヘルプメッセージを表示

#### 使用例

```bash
# カスタム設定での完全な解析
./js_analysis_pipeline.sh -d target.com \
    -o ./bug_bounty_results \
    -t 20 \
    -p both \
    -H "X-Bug-Bounty: your-id" \
    -H "Authorization: Bearer token"

# 認証付きプライベートプログラム
./js_analysis_pipeline.sh -d private.target.com \
    -H "X-Program: private-bounty" \
    -H "Cookie: session=abc123"
```

### js_download.py

ディレクトリ構造を保持しながらJavaScriptファイルをダウンロードするスタンドアロンPythonスクリプトです。

#### オプション

- `url_file`: JavaScriptのURLを含むファイル（1行に1つ）
- `-o, --output`: 出力ディレクトリ（デフォルト: ./js_files）
- `-H, --header`: カスタムヘッダーを追加（形式: "Key: Value"）
- `--header-file`: ファイルからヘッダーを読み込む（JSONまたはKey:Value形式）
- `-t, --threads`: 同時ダウンロード数（デフォルト: 10）
- `-v, --verbose`: 詳細出力

#### 使用例

```bash
# カスタムヘッダー付きでダウンロード
python js_download.py urls.txt -H "X-Bug-Bounty: hunter123"

# ファイルからヘッダーを読み込む
python js_download.py urls.txt --header-file headers.json

# カスタム出力ディレクトリとスレッド数
python js_download.py urls.txt -o ./downloads -t 5
```

#### ヘッダーファイルの形式

**JSON形式 (headers.json):**
```json
{
    "X-Bug-Bounty": "hunter123",
    "Authorization": "Bearer token123",
    "X-Program": "private-program"
}
```

**テキスト形式 (headers.txt):**
```
X-Bug-Bounty: hunter123
Authorization: Bearer token123
X-Program: private-program
```

## 🔍 解析出力

ツールキットは以下の解析ファイルを生成します：

### セキュリティ検出結果
- `potential_secrets.txt`: APIキー、トークン、パスワード
- `aws_keys.txt`: AWSアクセスキー
- `jwt_tokens.txt`: JWTトークン

### 抽出データ
- `endpoints.txt`: APIエンドポイントとURL
- `functions.txt`: JavaScript関数名
- `linkfinder_results.txt`: LinkFinderツールの結果
- `jsparser_results.txt`: JSParserツールの結果

### サマリーレポート
- `summary.txt`: すべての検出結果の包括的な概要

## 🛠️ 高度な使い方

### カスタム解析パイプライン

パイプラインスクリプトを修正して解析を拡張できます：

```bash
# カスタムgrepパターンを追加
grep -rHn -E "custom_pattern" "$JS_DIR" > "$ANALYSIS_DIR/custom_findings.txt"

# 追加ツールを統合
custom_tool --input "$JS_DIR" --output "$ANALYSIS_DIR/custom_results.txt"
```

### 自動化

複数のターゲット用のラッパースクリプトを作成：

```bash
#!/bin/bash
for domain in $(cat domains.txt); do
    ./js_analysis_pipeline.sh -d "$domain" -o "./results/$domain" \
        -H "X-Bug-Bounty: your-id"
done
```

## 🐛 バグバウンティのヒント

1. **認証ヘッダー**: プライベートプログラムには必要なヘッダーを必ず含める
2. **レート制限**: ターゲットのレート制限を尊重するためスレッド数を調整
3. **プロトコルテスト**: `-p both`を使用してリソースを見逃さないようにする
4. **定期的な更新**: 新しいJavaScriptファイルを検出するため定期的に解析を再実行

## 🤝 貢献

貢献を歓迎します！Pull Requestをお気軽に送信してください。

### 貢献のアイデア
- 追加の解析ツールのサポートを追加
- シークレット検出パターンの改善
- 出力形式オプション（JSON、CSV）の追加
- Webインターフェースの作成

## 📊 出力例

```
JavaScript Analysis Summary
==========================
Analysis Date: Thu Nov 14 2024
Target: example.com
Protocol: both
Total JS files: 42

Security Findings:
- Potential secrets found: 7
- AWS keys found: 2
- JWT tokens found: 3

Extracted Data:
- Unique endpoints found: 156
- Functions identified: 892
- LinkFinder results: 234
- JSParser results: 189
```

## ⚠️ 免責事項

このツールは承認されたセキュリティテストのみに使用してください。Webアプリケーションを解析する前に、必ず許可を得てください。作者はこのツールの誤用について責任を負いません。

## 📝 ライセンス

このプロジェクトはMITライセンスの下でライセンスされています - 詳細はLICENSEファイルを参照してください。

## 🙏 謝辞

- [getJS](https://github.com/003random/getJS) - JavaScriptファイル検出
- [LinkFinder](https://github.com/GerbenJavado/LinkFinder) - エンドポイント抽出
- [JSParser](https://github.com/nahamsec/JSParser) - JavaScript解析
- バグバウンティコミュニティ - インスピレーションとフィードバック

---

バグバウンティコミュニティのために ❤️ を込めて作成