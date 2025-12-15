#!/bin/bash
# checkcec.sh - Диагностика CEC процесса
# Использование: ./checkcec.sh
# Дата: 13.12.2025

echo "=== CEC Диагностика ==="
echo ""

# Проверка наличия процесса cec-client
echo "1. Проверка процесса cec-client..."
CEC_PROCESSES=$(ps aux | grep '[c]ec-client')

if [ -n "$CEC_PROCESSES" ]; then
    echo "✓ CEC процесс найден:"
    echo "$CEC_PROCESSES" | while read line; do
        echo "  $line"
    done
    
    # Подсчёт количества процессов
    CEC_COUNT=$(echo "$CEC_PROCESSES" | wc -l | tr -d ' ')
    echo ""
    echo "  Всего процессов cec-client: $CEC_COUNT"
else
    echo "✗ CEC процесс НЕ найден"
fi

echo ""
echo "=== Конец диагностики ==="
