#!/bin/bash

# フォルダー対応版JavaScriptフォーマットツール
# 使用方法: ./format-js-folder.sh /path/to/folder

# 引数チェック
# if [ $# -eq 0 ]; then
#     echo "使用方法: $0 <フォルダーパス または ファイルパス>"
#     echo "例: $0 ./js-files/"
#     echo "例: $0 ./script.js"
#     exit 1
# fi

# target="$1"

target=./js_analysis/js_files/

# ターゲットの存在チェック
if [ ! -e "$target" ]; then
    echo "エラー: '$target' が存在しません"
    exit 1
fi

# ファイルかフォルダーかを判定
if [ -f "$target" ]; then
    # ファイルの場合の処理
    echo "=== JavaScript フォーマットツール (ファイルモード) ==="
    echo "対象ファイル: $target"
    
    # ファイル拡張子チェック
    if [[ "$target" != *.js ]]; then
        echo "⚠️  警告: JavaScriptファイル(.js)ではありません"
        read -p "続行しますか？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "処理を中止しました"
            exit 0
        fi
    fi
    
    # ファイルをバックアップ
    backup_file="${target}.backup_$(date +%Y%m%d_%H%M%S)"
    echo "💾 バックアップ作成中..."
    cp "$target" "$backup_file"
    
    if [ $? -eq 0 ]; then
        echo "✅ バックアップ完了: $backup_file"
    else
        echo "❌ バックアップに失敗しました"
        exit 1
    fi
    
    echo ""
    echo "🔧 ファイルを整形中..."
    npx prettier@3.2.5 --write "$target"
    
    if [ $? -eq 0 ]; then
        echo "✅ 整形完了"
        echo ""
        echo "🎉 処理が完了しました！"
        echo "📄 整形済み: $target"
        echo "💾 バックアップ: $backup_file"
    else
        echo "❌ 整形に失敗しました (構文エラーまたは破損ファイルの可能性)"
        echo "💾 バックアップから復元: mv '$backup_file' '$target'"
    fi
    
    exit 0
fi

# フォルダーの場合の処理
if [ ! -d "$target" ]; then
    echo "エラー: '$target' はファイルでもフォルダーでもありません"
    exit 1
fi

folder="$target"

# フォルダー名から末尾のスラッシュを除去
folder=$(echo "$folder" | sed 's:/*$::')

# バックアップフォルダー名を生成
backup_folder="${folder}_backup_$(date +%Y%m%d_%H%M%S)"

echo "=== JavaScript フォーマットツール (フォルダーモード) ==="
echo "対象フォルダー: $folder"
echo "バックアップ先: $backup_folder"
echo ""

# フォルダー全体をバックアップ
echo "📁 フォルダーをバックアップ中..."
cp -r "$folder" "$backup_folder"
if [ $? -eq 0 ]; then
    echo "✅ バックアップ完了: $backup_folder"
else
    echo "❌ バックアップに失敗しました"
    exit 1
fi

echo ""

# JavaScriptファイルを検索して整形
echo "🔧 JavaScriptファイルを整形中..."
js_files=$(find "$folder" -name "*.js" -type f)

if [ -z "$js_files" ]; then
    echo "⚠️  JavaScriptファイルが見つかりませんでした"
    exit 0
fi

# ファイル数をカウント
file_count=$(echo "$js_files" | wc -l)
echo "📊 対象ファイル数: $file_count"
echo ""

# 各ファイルを整形
current=0
while IFS= read -r file; do
    current=$((current + 1))
    echo "[$current/$file_count] 整形中: $(basename "$file")"
    
    # Prettierで整形
    npx prettier@3.2.5 --write "$file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✅ 完了"
    else
        echo "  ❌ エラー (構文エラーまたは破損ファイルの可能性)"
    fi
done <<< "$js_files"

echo ""
echo "🎉 全ての処理が完了しました！"
echo "📁 元ファイル: $folder"
echo "💾 バックアップ: $backup_folder"
echo ""
echo "⚠️  問題があった場合は以下でバックアップから復元できます:"
echo "   rm -rf '$folder' && mv '$backup_folder' '$folder'"