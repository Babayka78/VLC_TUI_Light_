#!/bin/bash
# Version: 4
# Статус: Возврат в меню починен. BACK эмулирует Ctrl+C через kill -INT.
# Changelog V4: BACK кнопка отправляет kill -INT $$ для эмуляции Ctrl+C (быстрая очистка)
# Changelog V3: Добавлен pkill -9 cec-client при всех выходах
# Changelog V2: Исправлен баг с возвратом в меню при остановке VLC
#   - Заменён exit 0 на break в обработчике BACK кнопки
#   - Добавлена прогрессивная остановка VLC: quit → SIGTERM → SIGKILL → pkill
#   - Добавлены отладочные сообщения
#   - Заменён exit 0 на break в проверке VLC процесса

# Парсинг параметров: [секунды] файл
if [ $# -eq 2 ]; then
    START_TIME="$1"
    VIDEO_FILE="$2"
elif [ $# -eq 1 ]; then
    START_TIME=""
    VIDEO_FILE="$1"
else
    echo "Использование: $0 [секунды] <видеофайл>"
    exit 1
fi

if [ ! -f "$VIDEO_FILE" ]; then
    echo "❌ Файл не найден: $VIDEO_FILE"
    exit 1
fi

# ВАЖНО: Укажите ваше CEC устройство
CEC_DEVICE="/dev/cec1"

if [ ! -e "$CEC_DEVICE" ]; then
    echo "❌ CEC устройство не найдено: $CEC_DEVICE"
    echo "Доступные устройства:"
    ls -la /dev/cec* 2>/dev/null || echo "  Нет CEC устройств"
    exit 1
fi

echo "Запуск VLC с RC интерфейсом..."
echo "Для ручного управления: nc localhost 4212"
echo ""

# Запускаем VLC с RC интерфейсом
if [ -n "$START_TIME" ]; then
    cvlc --intf rc \
         --rc-host localhost:4212 \
         --fullscreen \
         --no-osd \
         --subsdec-encoding=Windows-1251 \
         "$VIDEO_FILE" :start-time=$START_TIME 2>&1 | grep -v "^\[" | grep -v "^VLC" | grep -v "^Command" &
else
    cvlc --intf rc \
         --rc-host localhost:4212 \
         --fullscreen \
         --no-osd \
         --subsdec-encoding=Windows-1251 \
         "$VIDEO_FILE" 2>&1 | grep -v "^\[" | grep -v "^VLC" | grep -v "^Command" &
fi

VLC_PID=$!
echo "VLC PID: $VLC_PID"

# Ждём пока VLC запустится
sleep 3

# Проверяем что VLC запущен
if ! kill -0 $VLC_PID 2>/dev/null; then
    echo "❌ Ошибка: VLC не запустился!"
    exit 1
fi

echo "✓ VLC запущен"
echo "✓ RC интерфейс: localhost:4212"
echo "✓ CEC мониторинг: $CEC_DEVICE"
echo ""
echo "🎮 Мониторинг пульта (нажмите любую кнопку для проверки)..."
echo ""

# Мониторим CEC с максимальной детализацией (построчная буферизация для while)
stdbuf -oL cec-client -d 8 -t r "$CEC_DEVICE" 2>&1 | while IFS= read -r line; do
    
    # Показываем все входящие команды для отладки (кроме polling и статус-запросов)
    if [[ "$line" == *"TRAFFIC"* ]] && [[ "$line" == *">>"* ]]; then
        # Пропускаем:
        # - f0, 10, 11 = polling messages
        # - 8f = Give Device Power Status
        # - 8c = Give Device Vendor ID
        # - 83 = Give Physical Address
        # - 46 = Give OSD Name
        # - 87 = Give Device Power Status response
        if [[ "$line" != *"f0"* ]] && \
           [[ "$line" != *"<< 10"* ]] && [[ "$line" != *"<< 11"* ]] && \
           [[ "$line" != *"01:8f"* ]] && [[ "$line" != *"01:8c"* ]] && \
           [[ "$line" != *"01:83"* ]] && [[ "$line" != *"01:46"* ]] && \
           [[ "$line" != *"01:87"* ]]; then
            echo "[CEC RAW] $line"
        fi
    fi

    # === ОБРАБОТКА КНОПОК ПУЛЬТА ===
    
    # OK → Play/Pause
    if [[ "$line" == *"44:00"* ]]; then
        echo "▶️  Play/Pause"
        echo "pause" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # UP → +30 sec
    if [[ "$line" == *"44:01"* ]]; then
        echo "⏩⏩ +30 sec"
        echo "seek +30" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # DOWN → -30 sec
    if [[ "$line" == *"44:02"* ]]; then
        echo "⏪⏪ -30 sec"
        echo "seek -30" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # LEFT → -10 sec
    if [[ "$line" == *"44:03"* ]]; then
        echo "⏪ -10 sec"
        echo "seek -10" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # RIGHT → +10 sec
    if [[ "$line" == *"44:04"* ]]; then
        echo "⏩ +10 sec"
        echo "seek +10" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # BACK → Exit (эмулируем Ctrl+C для быстрой очистки)
    if [[ "$line" == *"44:0d"* ]] || [[ "$line" == *"44:0D"* ]]; then
        echo "⏹️  Exit - возврат в меню"
        # Отправляем себе сигнал INT (эмуляция Ctrl+C)
        # Это вызовет trap cleanup который работает быстро
        kill -INT $$
        # После этого cleanup() выполнится и скрипт завершится
    fi

# INFO → Show time
    if [[ "$line" == *"44:35"* ]]; then
        echo "⏱️  Запрос времени..."
        
        time_output=$(echo "get_time" | nc -w 2 localhost 4212 2>&1)
        length_output=$(echo "get_length" | nc -w 2 localhost 4212 2>&1)
        
        current=$(echo "$time_output" | grep -oE '[0-9]+' | tail -1)
        total=$(echo "$length_output" | grep -oE '[0-9]+' | tail -1)
        
        if [ -n "$current" ] && [ -n "$total" ]; then
            remaining=$((total - current))
            current_fmt=$(printf "%02d:%02d:%02d" $((current/3600)) $((current%3600/60)) $((current%60)))
            total_fmt=$(printf "%02d:%02d:%02d" $((total/3600)) $((total%3600/60)) $((total%60)))
            remaining_fmt=$(printf "%02d:%02d:%02d" $((remaining/3600)) $((remaining%3600/60)) $((remaining%60)))
            echo "⏱️  $current_fmt / $total_fmt (осталось: $remaining_fmt)"
        else
            echo "⏱️  Ошибка получения времени"
        fi
        continue
    fi

# RED → Audio track (через -1 для корректного переключения)
    if [[ "$line" == *"44:72"* ]]; then
        echo "🔊 Audio track switch"
        # Сначала отключаем, потом включаем следующий
        echo "atrack -1" | nc -w 1 localhost 4212 >/dev/null 2>&1
        sleep 2
        current_atrack=$(echo "atrack" | nc -w 1 localhost 4212 2>&1 | grep -oE 'track [0-9-]+' | grep -oE '[0-9-]+' | head -1)
        if [ "$current_atrack" = "-1" ] || [ -z "$current_atrack" ]; then
            next_atrack=1
        else
            next_atrack=$((current_atrack + 1))
        fi
        echo "atrack $next_atrack" | nc -w 1 localhost 4212 >/dev/null 2>&1
        echo "   → Audio: track $next_atrack"
        continue
    fi
    
    # GREEN → Subtitles (циклическое переключение, включая выкл)
    if [[ "$line" == *"44:73"* ]]; then
        echo "📝 Subtitles switch"
        # Получаем текущие субтитры и переключаем (включая -1 = выкл)
        current_strack=$(echo "strack" | nc -w 1 localhost 4212 2>&1 | grep -oE 'track [0-9-]+' | grep -oE '[0-9-]+' | head -1)
        if [ -n "$current_strack" ]; then
            if [ "$current_strack" -eq "-1" ]; then
                next_strack=0
            else
                next_strack=$((current_strack + 1))
            fi
            echo "strack $next_strack" | nc -w 1 localhost 4212 >/dev/null 2>&1
            if [ "$next_strack" -eq "0" ]; then
                echo "   → Subtitles: ON (track $next_strack)"
            else
                echo "   → Subtitles: track $next_strack"
            fi
        fi
        continue
    fi
    
    # YELLOW → Volume +
    if [[ "$line" == *"44:74"* ]]; then
        echo "🔊 Volume +"
        echo "volup 1" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # BLUE → Volume -
    if [[ "$line" == *"44:71"* ]]; then
        echo "🔉 Volume -"
        echo "voldown 1" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # CHANNEL UP → +60 sec
    if [[ "$line" == *"44:30"* ]]; then
        echo "⏩⏩⏩ +60 sec"
        echo "seek +60" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # CHANNEL DOWN → -60 sec
    if [[ "$line" == *"44:31"* ]]; then
        echo "⏪⏪⏪ -60 sec"
        echo "seek -60" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
    # 0 → Start
    if [[ "$line" == *"44:20"* ]]; then
        echo "⏮️  To start"
        echo "seek 0" | nc -w 1 localhost 4212 >/dev/null 2>&1
        continue
    fi
    
# 1 → 10%
    if [[ "$line" == *"44:21"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 10%"
            echo "seek $((total * 10 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 2 → 20%
    if [[ "$line" == *"44:22"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 20%"
            echo "seek $((total * 20 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 3 → 30%
    if [[ "$line" == *"44:23"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 30%"
            echo "seek $((total * 30 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 4 → 40%
    if [[ "$line" == *"44:24"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 40%"
            echo "seek $((total * 40 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 5 → 50%
    if [[ "$line" == *"44:25"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 50%"
            echo "seek $((total * 50 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 6 → 60%
    if [[ "$line" == *"44:26"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 60%"
            echo "seek $((total * 60 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 7 → 70%
    if [[ "$line" == *"44:27"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 70%"
            echo "seek $((total * 70 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 8 → 80%
    if [[ "$line" == *"44:28"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 80%"
            echo "seek $((total * 80 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # 9 → 90%
    if [[ "$line" == *"44:29"* ]]; then
        total=$(echo "get_length" | nc -w 2 localhost 4212 2>&1 | grep -oE '[0-9]+' | tail -1)
        if [ -n "$total" ]; then
            echo "🎯 Jump to 90%"
            echo "seek $((total * 90 / 100))" | nc -w 1 localhost 4212 >/dev/null 2>&1
        fi
        continue
    fi
    
    # Проверяем что VLC ещё работает
    if ! kill -0 $VLC_PID 2>/dev/null; then
        echo "VLC завершён"
        break  # Выходим из цикла вместо exit 0
    fi
done &

CEC_PID=$!

# Функция для корректного завершения
cleanup() {
    echo ""
    echo "Завершение работы..."
    kill $CEC_PID 2>/dev/null
    kill $VLC_PID 2>/dev/null
    pkill -P $$ 2>/dev/null
    # Принудительно убиваем все cec-client процессы
    pkill -9 cec-client 2>/dev/null
    killall -9 cec-client 2>/dev/null
    # Не делаем exit 0, позволяем скрипту завершиться естественно
}

trap cleanup INT TERM

# Ждём завершения VLC
wait $VLC_PID

# После завершения VLC очищаем процессы
kill $CEC_PID 2>/dev/null
pkill -P $$ 2>/dev/null

# Убиваем все cec-client процессы для освобождения устройства
pkill -9 cec-client 2>/dev/null
killall -9 cec-client 2>/dev/null

# Возвращаем управление с кодом 0 для корректного возврата в меню
exit 0

