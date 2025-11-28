#!/bin/bash

# Путь к основному скрипту VLC-CEC
#VLC_SCRIPT="$HOME/vlc/vlc-cec.sh"
VLC_SCRIPT="./vlc-cec.sh"

# Подключаем библиотеку отслеживания прогресса воспроизведения
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/playback-tracker.sh"

# Начальная директория
START_DIR="$HOME/mac_disk"

# Проверка что скрипт VLC существует
if [ ! -f "$VLC_SCRIPT" ]; then
    echo "Ошибка: Скрипт $VLC_SCRIPT не найден!"
    echo "Создайте vlc-cec.sh в домашней директории"
    exit 1
fi

# Проверка что директория существует
if [ ! -d "$START_DIR" ]; then
    echo "Ошибка: Директория $START_DIR не найдена!"
    exit 1
fi

# Функция для отображения меню с dialog
show_menu() {
    local current_dir="$1"
    local default_item="$2"  # Опционально: на какой элемент вернуть курсор
    local title="Выбор видео: ${current_dir/#$HOME/~}"
    
    # Получаем список файлов и папок
    local items=()
    
    # Добавляем ".." если не в корне
    if [ "$current_dir" != "$START_DIR" ]; then
        items+=(".." "Назад")
    fi
    
    # Добавляем директории (только реальные папки, скрываем начинающиеся с точки)
    while IFS= read -r dir; do
        if [ -d "$current_dir/$dir" ] && [[ "$dir" != .* ]]; then
            items+=("$dir" "DIR")
        fi
    done < <(ls -1 "$current_dir" 2>/dev/null | sort)
    
    # Добавляем видео файлы (avi, mp4, mkv, mov, wmv, flv)
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local filesize=$(du -h "$file" | cut -f1)
        
        # Формируем описание с иконкой статуса и размером
        local description="$filesize"
        local status_icon=$(get_status_icon "$current_dir" "$filename")
        if [ -n "$status_icon" ]; then
            # Иконка + размер в описании
            description="${status_icon} ${filesize}"
        fi
        
        # В меню: tag = чистое имя файла (для hotkey), description = иконка + размер
        items+=("$filename" "$description")
    done < <(find "$current_dir" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" \) -print0 | sort -z)
    
    # Если нет элементов
    if [ ${#items[@]} -eq 0 ]; then
        dialog --title "Пусто" --msgbox "В этой директории нет видео файлов" 8 50
        return 1
    fi
    
    # Показываем меню (восстанавливаем TTY после VLC)
    # Явно восстанавливаем stdin/stdout на терминал
    exec < /dev/tty
    exec > /dev/tty
    
    # Вычисляем оптимальную ширину окна
    local max_width=120
    local longest_item=""
    local i=0
    while [ $i -lt ${#items[@]} ]; do
        local item_text="${items[$((i+1))]}"  # Берём описание (не ключ)
        local item_len=${#item_text}
        if [ $item_len -gt $max_width ]; then
            max_width=$item_len
            longest_item="$item_text"
        fi
        i=$((i + 2))  # Перескакиваем по парам (ключ, значение)
    done
    
    # Добавляем отступ для красоты и границ окна
    max_width=$((max_width + 10))
    
    # Минимальная ширина 120
    if [ $max_width -lt 120 ]; then
        max_width=120
    fi
    
    local choice
    if [ -n "$default_item" ]; then
        # Возвращаем курсор на указанный элемент
        choice=$(dialog --colors --output-fd 1 \
            --title "$title" \
            --default-item "$default_item" \
            --menu "Выберите файл или папку:" 20 $max_width 15 \
            "${items[@]}" \
            2>/dev/tty)
    else
        choice=$(dialog --colors --output-fd 1 \
            --title "$title" \
            --menu "Выберите файл или папку:" 20 $max_width 15 \
            "${items[@]}" \
            2>/dev/tty)
    fi
    
    local exit_code=$?
    
    # Обработка выбора
    if [ $exit_code -eq 0 ] && [ -n "$choice" ]; then
        # choice уже содержит чистое имя файла (без иконок)
        
        if [ "$choice" == ".." ]; then
            # Переход на уровень выше - возвращаем курсор на папку из которой вышли
            local parent_dir=$(dirname "$current_dir")
            local folder_name=$(basename "$current_dir")  # Название текущей папки
            if [ "$parent_dir" != "/" ]; then
                show_menu "$parent_dir" "$folder_name"
            else
                show_menu "$START_DIR"
            fi
        elif [ -d "$current_dir/$choice" ]; then
            # Переход в директорию
            show_menu "$current_dir/$choice"
        elif [ -f "$current_dir/$choice" ]; then
            # Запуск видео
            clear
            echo "Запуск: $choice"
            echo ""
            
            # Проверяем есть ли сохранённая позиция для видеофайла
            local progress=$(load_progress "$current_dir" "$choice")
            if [ -n "$progress" ]; then
                local saved_seconds=$(echo "$progress" | cut -d: -f1)
                local saved_percent=$(echo "$progress" | cut -d: -f3)
                
                # Показываем информацию о сохранённой позиции
                echo "Найдена сохранённая позиция: ${saved_percent}% ($(($saved_seconds / 60)) мин $(($saved_seconds % 60)) сек)"
                echo ""
                
                # Запуск VLC с сохранённой позиции (передаём секунды отдельным параметром)
                "$VLC_SCRIPT" "$saved_seconds" "$current_dir/$choice"
            else
                # Запуск с начала
                "$VLC_SCRIPT" "$current_dir/$choice"
            fi
            
	    # Автоматический возврат в меню - курсор на только что просмотренном видео
            show_menu "$current_dir" "$choice"
        fi
    elif [ $exit_code -eq 1 ]; then
        # Отмена - выход
        clear
        exit 0
    fi
}

# Проверка что установлен dialog
if ! command -v dialog &> /dev/null; then
    echo "Ошибка: Необходимо установить dialog"
    echo "Выполните: sudo apt-get install dialog"
    exit 1
fi

# Запуск меню
clear
show_menu "$START_DIR"
clear
