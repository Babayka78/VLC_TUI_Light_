#!/bin/bash
# Тест bash обёрток для skip markers

source ./db-manager.sh

echo "=== Тест 1: Получение skip markers (должно вернуть ошибку для новой записи) ==="
db_get_skip_markers "TestBash" "S01"
echo "Exit code: $?"
echo ""

echo "=== Тест 2: Установка intro markers (45-120s) ==="
db_set_intro_markers "TestBash" "S01" 45 120
if [ $? -eq 0 ]; then
    echo "✓ Intro markers установлены успешно"
else
    echo "✗ Ошибка установки intro markers"
fi
echo ""

echo "=== Тест 3: Проверка установленных intro markers ==="
db_get_skip_markers "TestBash" "S01"
echo ""

echo "=== Тест 4: Установка outro marker (3500s) ==="
db_set_outro_marker "TestBash" "S01" 3500
if [ $? -eq 0 ]; then
    echo "✓ Outro marker установлен успешно"
else
    echo "✗ Ошибка установки outro marker"
fi
echo ""

echo "=== Тест 5: Проверка всех markers ==="
db_get_skip_markers "TestBash" "S01"
echo ""

echo "=== Тест 6: Очистка intro markers ==="
db_clear_skip_markers "TestBash" "S01" intro
if [ $? -eq 0 ]; then
    echo "✓ Intro markers очищены успешно"
else
    echo "✗ Ошибка очистки"
fi
echo ""

echo "=== Тест 7: Проверка после очистки intro ==="
db_get_skip_markers "TestBash" "S01"
echo ""

echo "=== Все тесты завершены ==="
