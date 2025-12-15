#!/bin/bash
# cvlc.sh - кросс-платформенная обёртка для VLC
# Работает как /usr/bin/cvlc на Raspberry Pi

# Ищем vlc через команду which
VLC_PATH=$(which vlc 2>/dev/null)

if [ -z "$VLC_PATH" ]; then
    echo "❌ VLC не найден!"
    echo "Установите VLC:"
    echo "  macOS: brew install --cask vlc"
    echo "  Linux: sudo apt-get install vlc"
    exit 1
fi

# Определяем ОС
OS_TYPE=$(uname -s)

# Обрабатываем параметры в зависимости от ОС
if [[ "$OS_TYPE" == Darwin* ]]; then
    # ===== macOS =====
    # Проблема: --intf rc блокирует создание окна GUI
    # Решение: заменяем --intf rc на --extraintf rc
    
    # Заменяем --intf rc на --extraintf rc
    ARGS=("$@")
    NEW_ARGS=()
    
    i=0
    while [ $i -lt ${#ARGS[@]} ]; do
        if [ "${ARGS[$i]}" = "--intf" ] && [ "${ARGS[$((i+1))]}" = "rc" ]; then
            # Заменяем --intf rc на --extraintf rc
            NEW_ARGS+=("--extraintf")
            NEW_ARGS+=("rc")
            i=$((i + 2))
        else
            NEW_ARGS+=("${ARGS[$i]}")
            i=$((i + 1))
        fi
    done
    
    # Запускаем VLC с изменёнными параметрами (БЕЗ -I "dummy")
    exec "$VLC_PATH" "${NEW_ARGS[@]}"
    
else
    # ===== Linux/Raspberry Pi =====
    # Используем -I "dummy" как в оригинальном cvlc
    exec "$VLC_PATH" -I "dummy" "$@"
fi
