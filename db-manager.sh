#!/bin/bash

# db-manager.sh - Библиотека для работы с SQLite БД
# Версия: 0.1.0
# Дата: 29.11.2025

# Константы
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${SCRIPT_DIR}/vlc_media.db"

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ БД
# ============================================================================

# Создание БД и таблиц если их нет
db_init() {
    # Создание таблицы прогресса воспроизведения
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS playback (
    filename TEXT PRIMARY KEY,
    position INTEGER,
    duration INTEGER,
    percent INTEGER,
    series_key TEXT DEFAULT NULL,
    description TEXT DEFAULT NULL
);
EOF

    # Создание таблицы настроек сериалов
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS series_settings (
    series_key TEXT PRIMARY KEY,
    autoplay BOOLEAN DEFAULT 0,
    skip_intro BOOLEAN DEFAULT 0,
    skip_outro BOOLEAN DEFAULT 0,
    intro_start INTEGER DEFAULT NULL,
    intro_end INTEGER DEFAULT NULL,
    outro_start INTEGER DEFAULT NULL,
    description TEXT DEFAULT NULL
);
EOF
}

# ============================================================================
# УТИЛИТЫ
# ============================================================================

# Извлечение series_key из имени файла (паттерн S## E##)
# Параметры: $1 - filename
# Возвращает: "ShowName.S##" или пустую строку для фильмов
extract_series_key() {
    local filename="$1"
    
    # Проверяем паттерн S##E## или S##.E##
    if echo "$filename" | grep -qiE '[._\ ]S[0-9]{1,2}[._\ ]?E[0-9]{1,2}'; then
        # Извлекаем show_name (всё до .S## или _S## или " S##")
        local show_name=$(echo "$filename" | sed -E 's/([._\ ]S[0-9]{1,2}[._\ ]?E[0-9]{1,2}).*//' | sed 's/[._ ]*$//')
        
        # Извлекаем номер сезона
        local season=$(echo "$filename" | sed -E 's/.*[._\ ]S([0-9]{1,2})[._\ ]?E[0-9]{1,2}.*/\1/')
        
        # Убрать leading zeros для правильного форматирования
        season=$(echo "$season" | sed 's/^0*//')
        [ -z "$season" ] && season=0
        
        # Форматировать с leading zero
        local season_padded=$(printf "%02d" "$season")
        
       echo "${show_name}.S${season_padded}"
    else
        echo ""  # Не сериал
    fi
}

# ============================================================================
# PLAYBACK ФУНКЦИИ
# ============================================================================

# Сохранение прогресса воспроизведения
# Параметры: $1 - filename, $2 - position, $3 - duration, $4 - percent, $5 - series_key (optional)
db_save_playback() {
    local filename="$1"
    local position="$2"
    local duration="$3"
    local percent="$4"
    local series_key="${5:-NULL}"
    
    # Если series_key пустая строка, заменяем на NULL
    if [ -z "$series_key" ]; then
        series_key="NULL"
    else
        series_key="'$series_key'"
    fi
    
    sqlite3 "$DB_PATH" <<EOF
INSERT INTO playback (filename, position, duration, percent, series_key)
VALUES ('$filename', $position, $duration, $percent, $series_key)
ON CONFLICT(filename) DO UPDATE SET
    position = $position,
    duration = $duration,
    percent = $percent,
    series_key = $series_key;
EOF
}

# Получение данных воспроизведения
# Параметры: $1 - filename
# Возвращает: position|duration|percent|series_key
db_get_playback() {
    local filename="$1"
    
    sqlite3 "$DB_PATH" <<EOF
SELECT position, duration, percent, COALESCE(series_key, '')
FROM playback
WHERE filename = '$filename';
EOF
}

# Получение процента просмотра
# Параметры: $1 - filename
# Возвращает: percent (0 если нет записи)
db_get_playback_percent() {
    local filename="$1"
    
    local result=$(sqlite3 "$DB_PATH" "SELECT percent FROM playback WHERE filename = '$filename';")
    
    if [ -z "$result" ]; then
        echo "0"
    else
        echo "$result"
    fi
}

# ============================================================================
# SERIES SETTINGS ФУНКЦИИ
# ============================================================================

# Сохранение настроек сериала
# Параметры: $1 - series_key, $2 - autoplay, $3 - skip_intro, $4 - skip_outro,
#            $5 - intro_start, $6 - intro_end, $7 - outro_start
db_save_series_settings() {
    local series_key="$1"
    local autoplay="$2"
    local skip_intro="$3"
    local skip_outro="$4"
    local intro_start="${5:-NULL}"
    local intro_end="${6:-NULL}"
    local outro_start="${7:-NULL}"
    
    sqlite3 "$DB_PATH" <<EOF
INSERT INTO series_settings (series_key, autoplay, skip_intro, skip_outro, intro_start, intro_end, outro_start)
VALUES ('$series_key', $autoplay, $skip_intro, $skip_outro, $intro_start, $intro_end, $outro_start)
ON CONFLICT(series_key) DO UPDATE SET
    autoplay = $autoplay,
    skip_intro = $skip_intro,
    skip_outro = $skip_outro,
    intro_start = $intro_start,
    intro_end = $intro_end,
    outro_start = $outro_start;
EOF
}

# Получение настроек сериала
# Параметры: $1 - series_key
# Возвращает: autoplay|skip_intro|skip_outro|intro_start|intro_end|outro_start
db_get_series_settings() {
    local series_key="$1"
    
    sqlite3 "$DB_PATH" <<EOF
SELECT autoplay, skip_intro, skip_outro, 
       COALESCE(intro_start, ''), COALESCE(intro_end, ''), COALESCE(outro_start, '')
FROM series_settings
WHERE series_key = '$series_key';
EOF
}

# Проверка существования настроек
# Параметры: $1 - series_key
# Возвращает: 0 если есть, 1 если нет
db_series_settings_exist() {
    local series_key="$1"
    
    local result=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM series_settings WHERE series_key = '$series_key';")
    
    if [ "$result" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# ТЕСТОВЫЕ/DEBUG ФУНКЦИИ (только для разработки)
# ============================================================================

# Запись debug данных в description
# Параметры: $1 - filename, $2 - debug_data
db_save_debug_info() {
    local filename="$1"
    local debug_data="$2"
    
    sqlite3 "$DB_PATH" <<EOF
UPDATE playback
SET description = '$debug_data'
WHERE filename = '$filename';
EOF
}

# Чтение debug данных из description
# Параметры: $1 - filename
# Возвращает: содержимое description
db_get_debug_info() {
    local filename="$1"
    
    sqlite3 "$DB_PATH" "SELECT COALESCE(description, '') FROM playback WHERE filename = '$filename';"
}

# ============================================================================
# АВТОИНИЦИАЛИЗАЦИЯ
# ============================================================================

# Инициализируем БД при загрузке библиотеки
db_init
