#!/bin/bash
# series-tracker.sh
# Библиотека для отслеживания прогресса просмотра сериалов
# Использование: source "$HOME/vlc/series-tracker.sh"

# ============================================================
# НАСТРОЙКИ (можно изменять для тонкой настройки)
# ============================================================

# Паттерн для определения сериалов
# Поддерживает S##E## с любыми разделителями: . - _ пробел или без разделителя
# Примеры: S01E01, S01.E01, S01-E01, S01_E01, S01 E01
SERIES_PATTERN='S[0-9][0-9][-_. ]*E[0-9][0-9]'

# Пороги процентов просмотра
WATCHED_THRESHOLD=99     # Процент для [X] - просмотрено
PARTIAL_THRESHOLD=1      # Минимальный процент для [T] - частично

# Интервал мониторинга в секундах
MONITOR_INTERVAL=60

# ============================================================
# ФУНКЦИИ
# ============================================================

# Проверяет является ли файл сериалом по паттерну
# Использование: is_series_file "filename"
# Возвращает: 0 если сериал, 1 если нет
is_series_file() {
    local filename="$1"
    
    if [[ "$filename" =~ $SERIES_PATTERN ]]; then
        return 0
    fi
    
    return 1
}

# Извлекает код эпизода (S##E##) из имени файла
# Использование: get_episode_code "filename"
# Возвращает: S01E01 или пустую строку
get_episode_code() {
    local filename="$1"
    
    # Ищем паттерн S##...E##
    if [[ "$filename" =~ $SERIES_PATTERN ]]; then
        local matched="${BASH_REMATCH[0]}"
        
        # Извлекаем S## и E## части
        local season=$(echo "$matched" | grep -oE 'S[0-9][0-9]')
        local episode=$(echo "$matched" | grep -oE 'E[0-9][0-9]')
        
        if [ -n "$season" ] && [ -n "$episode" ]; then
            # Возвращаем нормализованный формат S##E##
            echo "${season}${episode}"
            return 0
        fi
    fi
    
    # Ничего не найдено
    echo ""
    return 1
}

# Возвращает путь к .ser файлу для директории
# Использование: get_ser_file "/path/to/series/dir"
# Возвращает: /path/to/series/dir/.ser
get_ser_file() {
    local dir="$1"
    echo "$dir/.ser"
}

# Загружает прогресс просмотра для файла из .ser
# Использование: load_progress "/path/to/dir" "filename"
# Возвращает: "seconds:total:percent" или пустую строку
load_progress() {
    local dir="$1"
    local filename="$2"
    local ser_file=$(get_ser_file "$dir")
    
    if [ ! -f "$ser_file" ]; then
        echo ""
        return 1
    fi
    
    # Ищем строку с filename
    local line=$(grep "^${filename}:" "$ser_file" 2>/dev/null)
    
    if [ -z "$line" ]; then
        echo ""
        return 1
    fi
    
    # Формат: filename:seconds:total:percent:timestamp
    # Возвращаем: seconds:total:percent
    echo "$line" | cut -d: -f2-4
    return 0
}

# Сохраняет прогресс просмотра в .ser файл
# Использование: save_progress "/path/to/dir" "filename" seconds total percent
save_progress() {
    local dir="$1"
    local filename="$2"
    local seconds="$3"
    local total="$4"
    local percent="$5"
    local ser_file=$(get_ser_file "$dir")
    local timestamp=$(date +%s)
    
    # Создаём временный файл
    local temp_file="${ser_file}.tmp"
    
    # Если .ser не существует - создаём новый
    if [ ! -f "$ser_file" ]; then
        echo "${filename}:${seconds}:${total}:${percent}:${timestamp}" > "$ser_file"
        return 0
    fi
    
    # Обновляем существующую запись или добавляем новую
    local found=0
    while IFS= read -r line; do
        if [[ "$line" == "${filename}:"* ]]; then
            # Обновляем существующую запись
            echo "${filename}:${seconds}:${total}:${percent}:${timestamp}" >> "$temp_file"
            found=1
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$ser_file"
    
    # Если не нашли - добавляем новую запись
    if [ $found -eq 0 ]; then
        echo "${filename}:${seconds}:${total}:${percent}:${timestamp}" >> "$temp_file"
    fi
    
    # Заменяем файл
    mv "$temp_file" "$ser_file"
    return 0
}

# Возвращает иконку статуса для файла
# Использование: get_status_icon "/path/to/dir" "filename"
# Возвращает: "[ ]" "[T]" или "[X]"
get_status_icon() {
    local dir="$1"
    local filename="$2"
    
    # Проверяем что это сериал
    if ! is_series_file "$filename"; then
        echo ""
        return 1
    fi
    
    # Загружаем прогресс
    local progress=$(load_progress "$dir" "$filename")
    
    if [ -z "$progress" ]; then
        # Нет прогресса - не просмотрено
        echo "[ ]"
        return 0
    fi
    
    # Извлекаем процент
    local percent=$(echo "$progress" | cut -d: -f3)
    
    # Определяем иконку по порогам
    if [ "$percent" -ge "$WATCHED_THRESHOLD" ]; then
        echo "[X]"
    elif [ "$percent" -ge "$PARTIAL_THRESHOLD" ]; then
        echo "[T]"
    else
        echo "[ ]"
    fi
    
    return 0
}

# Возвращает процент просмотра для файла
# Использование: get_progress_percent "/path/to/dir" "filename"
# Возвращает: процент (0-100) или 0 если нет данных
get_progress_percent() {
    local dir="$1"
    local filename="$2"
    
    local progress=$(load_progress "$dir" "$filename")
    
    if [ -z "$progress" ]; then
        echo "0"
        return 0
    fi
    
    # Извлекаем процент
    echo "$progress" | cut -d: -f3
    return 0
}
