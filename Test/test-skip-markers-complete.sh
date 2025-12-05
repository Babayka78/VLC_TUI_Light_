#!/bin/bash
# Комплексный тест Skip Intro/Outro функциональности
# Выполняется на Raspberry Pi

cd "$(dirname "$0")/.."
source ./db-manager.sh

echo "=========================================="
echo "Тест Skip Intro/Outro - Полная проверка"
echo "=========================================="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_passed=0
test_failed=0

# Функция для проверки результата
check_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((test_passed++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((test_failed++))
    fi
}

echo "=== ТЕСТ 1: Проверка функций конвертации времени ==="
echo ""

# Тест seconds_to_mmss
source ./serials.sh
result=$(seconds_to_mmss 90)
[ "$result" == "01:30" ]
check_result $? "seconds_to_mmss(90) = 01:30"

result=$(seconds_to_mmss 3665)
[ "$result" == "61:05" ]
check_result $? "seconds_to_mmss(3665) = 61:05"

result=$(seconds_to_mmss "")
[ -z "$result" ]
check_result $? "seconds_to_mmss('') = пустая строка"

# Тест mmss_to_seconds
result=$(mmss_to_seconds "01:30")
[ "$result" == "90" ]
check_result $? "mmss_to_seconds(01:30) = 90"

result=$(mmss_to_seconds "61:05")
[ "$result" == "3665" ]
check_result $? "mmss_to_seconds(61:05) = 3665"

result=$(mmss_to_seconds "")
[ -z "$result" ]
check_result $? "mmss_to_seconds('') = пустая строка"

echo ""
echo "=== ТЕСТ 2: Операции с БД (vlc_db.py) ==="
echo ""

# Очистка тестовых данных
python3 vlc_db.py clear-skip "TestMarkers" "S01" all >/dev/null 2>&1

# Установка intro markers
python3 vlc_db.py set-intro "TestMarkers" "S01" 30 90 >/dev/null 2>&1
check_result $? "set-intro: Установка intro markers (30s-90s)"

# Проверка через get-skip-markers
markers=$(python3 vlc_db.py get-skip-markers "TestMarkers" "S01" 2>/dev/null)
echo "$markers" | grep -q '"intro_start": 30'
check_result $? "get-skip-markers: intro_start = 30"

echo "$markers" | grep -q '"intro_end": 90'
check_result $? "get-skip-markers: intro_end = 90"

# Установка outro marker
python3 vlc_db.py set-outro "TestMarkers" "S01" 3300 >/dev/null 2>&1
check_result $? "set-outro: Установка outro marker (3300s)"

markers=$(python3 vlc_db.py get-skip-markers "TestMarkers" "S01" 2>/dev/null)
echo "$markers" | grep -q '"outro_start": 3300'
check_result $? "get-skip-markers: outro_start = 3300"

# Очистка intro
python3 vlc_db.py clear-skip "TestMarkers" "S01" intro >/dev/null 2>&1
check_result $? "clear-skip: Очистка intro markers"

markers=$(python3 vlc_db.py get-skip-markers "TestMarkers" "S01" 2>/dev/null)
echo "$markers" | grep -q '"intro_start": null'
check_result $? "get-skip-markers: intro_start = null после очистки"

# Очистка всех markers
python3 vlc_db.py clear-skip "TestMarkers" "S01" all >/dev/null 2>&1
check_result $? "clear-skip: Очистка всех markers"

echo ""
echo "=== ТЕСТ 3: Bash обёртки (db-manager.sh) ==="
echo ""

# Установка через bash функции
db_set_intro_markers "TestBash" "S01" 45 120
check_result $? "db_set_intro_markers: Установка через bash"

result=$(db_get_skip_markers "TestBash" "S01" 2>/dev/null)
echo "$result" | grep -q '"intro_start": 45'
check_result $? "db_get_skip_markers: Проверка intro_start через bash"

db_clear_skip_markers "TestBash" "S01" "all"
check_result $? "db_clear_skip_markers: Очистка через bash"

echo ""
echo "=== ТЕСТ 4: Валидация данных ==="
echo ""

# Попытка установить intro с end < start (должна провалиться)
python3 vlc_db.py set-intro "TestValidation" "S01" 100 50 >/dev/null 2>&1
[ $? -ne 0 ]
check_result $? "Валидация: intro_end < intro_start возвращает ошибку"

# Попытка установить отрицательные значения
python3 vlc_db.py set-intro "TestValidation" "S01" -10 50 >/dev/null 2>&1
[ $? -ne 0 ]
check_result $? "Валидация: отрицательные значения возвращают ошибку"

echo ""
echo "=========================================="
echo "ИТОГИ ТЕСТИРОВАНИЯ"
echo "=========================================="
echo -e "${GREEN}Пройдено:${NC} $test_passed"
echo -e "${RED}Провалено:${NC} $test_failed"
echo ""

if [ $test_failed -eq 0 ]; then
    echo -e "${GREEN}✓ ВСЕ ТЕСТЫ ПРОЙДЕНЫ!${NC}"
    exit 0
else
    echo -e "${RED}✗ НЕКОТОРЫЕ ТЕСТЫ ПРОВАЛЕНЫ${NC}"
    exit 1
fi
