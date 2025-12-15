#!/bin/bash

# platform-utils.sh
# Кросс-платформенные utility-функции для совместимости между macOS (BSD) и Linux (GNU)
# Версия: 1.0.0
# Дата: 15.12.2025

# ============================================================================
# Определение операционной системы
# ============================================================================

# Определяет текущую ОС
# Возвращает: "macos", "linux", или "unknown"
detect_os() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

# ============================================================================
# Кросс-платформенная сортировка
# ============================================================================

# Сортировка с null-разделителями (совместимо с BSD и GNU)
# Использование: find ... -print0 | platform_sort_null
# 
# Детали:
# - macOS (BSD sort): не поддерживает флаг -z, используем обычный sort
# - Linux (GNU sort): поддерживает -z для null-разделителей
#
# Примечание: На macOS файлы будут отсортированы, но разделители останутся null
platform_sort_null() {
    local os=$(detect_os)
    
    if [ "$os" = "macos" ]; then
        # macOS: sort не поддерживает -z
        # Используем tr для замены null на newline, сортируем, возвращаем null
        tr '\0' '\n' | sort | tr '\n' '\0'
    else
        # Linux: используем -z для сортировки с null-разделителями
        sort -z
    fi
}

# ============================================================================
# Кросс-платформенная работа со временем
# ============================================================================

# Получение текущего timestamp в секундах
# Возвращает: количество секунд с Unix epoch
#
# Детали:
# - macOS (BSD date): не поддерживает %N (наносекунды)
# - Linux (GNU date): поддерживает %s.%N
# - Для совместимости используем только секунды (%s)
platform_timestamp() {
    date +%s
}

# Вычисление разницы между двумя timestamp
# Аргументы:
#   $1 - начальное время (секунды)
#   $2 - конечное время (секунды)
# Возвращает: разница в секундах
#
# Детали:
# - Если bc установлен - используем для точности
# - Если bc нет - используем целочисленную арифметику bash
platform_time_diff() {
    local start="$1"
    local end="$2"
    
    # Проверяем наличие bc
    if command -v bc &>/dev/null; then
        # Используем bc для вычислений с плавающей точкой
        echo "$end - $start" | bc
    else
        # Fallback: целочисленная арифметика (bash)
        echo $((end - start))
    fi
}

# ============================================================================
# Информация о платформе (для отладки)
# ============================================================================

# Выводит информацию о текущей платформе
# Использование: platform_info
platform_info() {
    echo "=== Platform Information ==="
    echo "OS Type: $(detect_os)"
    echo "OSTYPE: $OSTYPE"
    echo "Bash Version: $BASH_VERSION"
    echo ""
    echo "Available Commands:"
    echo "  sort: $(command -v sort || echo 'NOT FOUND')"
    echo "  date: $(command -v date || echo 'NOT FOUND')"
    echo "  bc: $(command -v bc || echo 'NOT FOUND')"
    echo ""
    # Тест поддержки sort -z (без warning)
    if printf "test1\0test2" 2>/dev/null | sort -z 2>/dev/null 1>/dev/null; then
        echo "Sort supports -z: YES"
    else
        echo "Sort supports -z: NO"
    fi
    echo "Date supports %N: $(date +%s.%N 2>/dev/null | grep -q '\.' && echo 'YES' || echo 'NO')"
}

# ============================================================================
# Тесты (для проверки функциональности)
# ============================================================================

# Запускает тесты всех функций
# Использование: platform_test
platform_test() {
    echo "=== Platform Utils Test Suite ==="
    echo ""
    
    # Тест 1: Определение ОС
    echo "Test 1: detect_os"
    local os=$(detect_os)
    echo "  Result: $os"
    if [ "$os" = "macos" ] || [ "$os" = "linux" ]; then
        echo "  ✓ PASS"
    else
        echo "  ✗ FAIL (unknown OS)"
    fi
    echo ""
    
    # Тест 2: Timestamp
    echo "Test 2: platform_timestamp"
    local ts=$(platform_timestamp)
    echo "  Result: $ts"
    if [[ "$ts" =~ ^[0-9]+$ ]]; then
        echo "  ✓ PASS"
    else
        echo "  ✗ FAIL (not a number)"
    fi
    echo ""
    
    # Тест 3: Time diff
    echo "Test 3: platform_time_diff"
    local start=$(platform_timestamp)
    sleep 1
    local end=$(platform_timestamp)
    local diff=$(platform_time_diff "$start" "$end")
    echo "  Start: $start"
    echo "  End: $end"
    echo "  Diff: $diff seconds"
    if [ "$diff" -ge 1 ] && [ "$diff" -le 2 ]; then
        echo "  ✓ PASS"
    else
        echo "  ✗ FAIL (expected ~1 second)"
    fi
    echo ""
    
    # Тест 4: Sort null
    echo "Test 4: platform_sort_null"
    # Используем printf для корректной генерации null-разделителей
    local sorted=$(printf "file3.mkv\0file1.mkv\0file2.mkv" | platform_sort_null | tr '\0' '\n')
    echo "  Input: file3.mkv, file1.mkv, file2.mkv"
    echo "  Output:"
    echo "$sorted" | sed 's/^/    /'
    if echo "$sorted" | head -1 | grep -q "file1.mkv"; then
        echo "  ✓ PASS (correctly sorted)"
    else
        echo "  ✗ FAIL (not sorted correctly)"
    fi
    echo ""
    
    echo "=== Test Complete ==="
}

# ============================================================================
# Экспорт функций (если скрипт source'ится)
# ============================================================================

# Если скрипт запущен напрямую (не через source), показываем информацию
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "platform-utils.sh - Cross-platform utility library"
    echo ""
    echo "Usage:"
    echo "  source platform-utils.sh    # Load functions into current shell"
    echo "  ./platform-utils.sh info    # Show platform information"
    echo "  ./platform-utils.sh test    # Run test suite"
    echo ""
    
    # Обработка аргументов
    case "${1:-}" in
        info)
            platform_info
            ;;
        test)
            platform_test
            ;;
        *)
            echo "Available functions:"
            echo "  detect_os()"
            echo "  platform_sort_null()"
            echo "  platform_timestamp()"
            echo "  platform_time_diff(start, end)"
            echo "  platform_info()"
            echo "  platform_test()"
            ;;
    esac
fi
