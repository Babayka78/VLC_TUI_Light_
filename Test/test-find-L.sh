#!/bin/bash

# Тест find с опцией -L для симлинков
echo "=== Тест find -L ==="
echo ""

TEST_DIR="${1:-$HOME/T7}"
echo "Директория: $TEST_DIR"
echo ""

echo "--- Тест 1: find БЕЗ -L ---"
find "$TEST_DIR" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" \) -print | wc -l
echo ""

echo "--- Тест 2: find С -L ---"
find -L "$TEST_DIR" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" \) -print | wc -l
echo ""

echo "--- Тест 3: ls директории ---"
ls -la "$TEST_DIR" | grep -E "\.(avi|mkv)" | wc -l
echo ""

echo "--- Тест 4: Проверка типа директории ---"
ls -ld "$TEST_DIR"
echo ""

echo "--- Тест 5: Реальный путь ---"
if [ -L "$TEST_DIR" ]; then
    echo "Это симлинк!"
    echo "Указывает на: $(readlink "$TEST_DIR")"
else
    echo "Это НЕ симлинк"
fi
