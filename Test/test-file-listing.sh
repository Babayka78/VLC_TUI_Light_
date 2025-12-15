#!/bin/bash

# Тестовый скрипт для диагностики поиска видеофайлов на macOS
# Дата: 15.12.2025
# Цель: Выявить причину отсутствия отображения файлов в корне T7

echo "=== Тест поиска видеофайлов ==="
echo ""

# Подключаем platform-utils для использования platform_sort_null
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/platform-utils.sh"

# Определяем ОС
OS=$(detect_os)
echo "Операционная система: $OS"
echo "Bash версия: $BASH_VERSION"
echo ""

# Тестовая директория (можно передать как параметр)
TEST_DIR="${1:-$HOME}"
echo "Тестовая директория: $TEST_DIR"
echo ""

# Проверка существования директории
if [ ! -d "$TEST_DIR" ]; then
    echo "❌ Ошибка: Директория не существует!"
    exit 1
fi

echo "--- Тест 1: Простой ls ---"
ls -la "$TEST_DIR" | head -20
echo ""

echo "--- Тест 2: find с -print (обычный вывод) ---"
find "$TEST_DIR" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" \) -print
echo ""

echo "--- Тест 3: find с -print0 (null-разделители) ---"
echo "Количество файлов (через wc):"
find "$TEST_DIR" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" \) -print0 | tr '\0' '\n' | wc -l
echo ""

echo "--- Тест 4: find + platform_sort_null (как в video-menu.sh) ---"
echo "Список файлов:"
video_filenames=()
while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    video_filenames+=("$filename")
    echo "  - $filename"
done < <(find "$TEST_DIR" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" \) -print0 | platform_sort_null)

echo ""
echo "Всего найдено файлов: ${#video_filenames[@]}"
echo ""

echo "--- Тест 5: Проверка прав доступа ---"
echo "Права на директорию:"
ls -ld "$TEST_DIR"
echo ""

echo "--- Тест 6: Проверка скрытых файлов ---"
echo "Файлы начинающиеся с точки:"
ls -la "$TEST_DIR" | grep "^\." | head -5
echo ""

echo "=== Тест завершён ==="
