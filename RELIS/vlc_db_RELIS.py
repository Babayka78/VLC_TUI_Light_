#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
vlc_db.py - Библиотека для безопасной работы с SQLite БД
Версия: 1.0.0
Дата: 02.12.2025

Защита от SQL Injection через параметризованные запросы.
CLI интерфейс для вызова из bash скриптов.
"""

import sqlite3
import sys
import os
import json
from pathlib import Path
from typing import Optional, Tuple, List, Dict, Any

# Константы
SCRIPT_DIR = Path(__file__).parent.resolve()
DB_PATH = SCRIPT_DIR / "vlc_media.db"


class VlcDatabase:
    """Класс для работы с БД VLC медиаплеера"""
    
    def __init__(self, db_path: Path = DB_PATH):
        """Инициализация подключения к БД"""
        self.db_path = db_path
        self.conn = None
        self.cursor = None
    
    def __enter__(self):
        """Контекстный менеджер - вход"""
        self.conn = sqlite3.connect(str(self.db_path))
        self.cursor = self.conn.cursor()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Контекстный менеджер - выход"""
        if self.conn:
            if exc_type is None:
                self.conn.commit()
            else:
                self.conn.rollback()
            self.conn.close()
    
    def init_db(self) -> bool:
        """Инициализация БД - создание таблиц если их нет"""
        try:
            # Таблица прогресса воспроизведения
            self.cursor.execute("""
                CREATE TABLE IF NOT EXISTS playback (
                    filename TEXT PRIMARY KEY,
                    position INTEGER,
                    duration INTEGER,
                    percent INTEGER,
                    series_prefix TEXT DEFAULT NULL,
                    series_suffix TEXT DEFAULT NULL,
                    description TEXT DEFAULT NULL
                )
            """)
            
            # Таблица настроек сериалов
            self.cursor.execute("""
                CREATE TABLE IF NOT EXISTS series_settings (
                    series_prefix TEXT NOT NULL,
                    series_suffix TEXT NOT NULL,
                    autoplay BOOLEAN DEFAULT 0,
                    skip_intro BOOLEAN DEFAULT 0,
                    skip_outro BOOLEAN DEFAULT 0,
                    intro_start INTEGER DEFAULT NULL,
                    intro_end INTEGER DEFAULT NULL,
                    outro_start INTEGER DEFAULT NULL,
                    description TEXT DEFAULT NULL,
                    PRIMARY KEY (series_prefix, series_suffix)
                )
            """)
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка инициализации БД: {e}", file=sys.stderr)
            return False
    
    def save_playback(self, filename: str, position: int, duration: int, 
                     percent: int, series_prefix: Optional[str] = None, 
                     series_suffix: Optional[str] = None) -> bool:
        """Сохранение прогресса воспроизведения (защита от SQL injection)"""
        try:
            self.cursor.execute("""
                INSERT INTO playback (filename, position, duration, percent, series_prefix, series_suffix)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(filename) DO UPDATE SET
                    position = ?,
                    duration = ?,
                    percent = ?,
                    series_prefix = ?,
                    series_suffix = ?
            """, (filename, position, duration, percent, series_prefix, series_suffix,
                  position, duration, percent, series_prefix, series_suffix))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка сохранения playback: {e}", file=sys.stderr)
            return False
    
    def get_playback(self, filename: str) -> Optional[Tuple[int, int, int, str, str]]:
        """Получение данных воспроизведения
        
        Возвращает: (position, duration, percent, series_prefix, series_suffix)
        """
        try:
            self.cursor.execute("""
                SELECT position, duration, percent, 
                       COALESCE(series_prefix, ''), 
                       COALESCE(series_suffix, '')
                FROM playback
                WHERE filename = ?
            """, (filename,))
            
            result = self.cursor.fetchone()
            return result if result else None
        except sqlite3.Error as e:
            print(f"Ошибка получения playback: {e}", file=sys.stderr)
            return None
    
    def get_playback_percent(self, filename: str) -> int:
        """Получение процента просмотра
        
        Возвращает: percent (0 если нет записи)
        """
        try:
            self.cursor.execute("""
                SELECT percent FROM playback WHERE filename = ?
            """, (filename,))
            
            result = self.cursor.fetchone()
            return result[0] if result else 0
        except sqlite3.Error as e:
            print(f"Ошибка получения percent: {e}", file=sys.stderr)
            return 0
    
    def save_series_settings(self, series_prefix: str, series_suffix: str,
                            autoplay: bool, skip_intro: bool, skip_outro: bool,
                            intro_start: Optional[int] = None,
                            intro_end: Optional[int] = None,
                            outro_start: Optional[int] = None) -> bool:
        """Сохранение настроек сериала (защита от SQL injection)"""
        try:
            self.cursor.execute("""
                INSERT INTO series_settings 
                (series_prefix, series_suffix, autoplay, skip_intro, skip_outro, 
                 intro_start, intro_end, outro_start)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(series_prefix, series_suffix) DO UPDATE SET
                    autoplay = ?,
                    skip_intro = ?,
                    skip_outro = ?,
                    intro_start = ?,
                    intro_end = ?,
                    outro_start = ?
            """, (series_prefix, series_suffix, autoplay, skip_intro, skip_outro,
                  intro_start, intro_end, outro_start,
                  autoplay, skip_intro, skip_outro, intro_start, intro_end, outro_start))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка сохранения настроек сериала: {e}", file=sys.stderr)
            return False
    
    def get_series_settings(self, series_prefix: str, series_suffix: str) -> Optional[Tuple]:
        """Получение настроек сериала
        
        Возвращает: (autoplay, skip_intro, skip_outro, intro_start, intro_end, outro_start)
        """
        try:
            self.cursor.execute("""
                SELECT autoplay, skip_intro, skip_outro,
                       COALESCE(intro_start, ''), 
                       COALESCE(intro_end, ''), 
                       COALESCE(outro_start, '')
                FROM series_settings
                WHERE series_prefix = ? AND series_suffix = ?
            """, (series_prefix, series_suffix))
            
            result = self.cursor.fetchone()
            return result if result else None
        except sqlite3.Error as e:
            print(f"Ошибка получения настроек: {e}", file=sys.stderr)
            return None
    
    def series_settings_exist(self, series_prefix: str, series_suffix: str) -> bool:
        """Проверка существования настроек сериала"""
        try:
            self.cursor.execute("""
                SELECT COUNT(*) FROM series_settings 
                WHERE series_prefix = ? AND series_suffix = ?
            """, (series_prefix, series_suffix))
            
            result = self.cursor.fetchone()
            return result[0] > 0 if result else False
        except sqlite3.Error as e:
            print(f"Ошибка проверки настроек: {e}", file=sys.stderr)
            return False
    
    def find_other_versions(self, series_prefix: str, current_suffix: str) -> List[Tuple[str, str, int]]:
        """Поиск других версий сериала с тем же prefix, но другим suffix
        
        Возвращает: список (suffix, last_filename, max_percent)
        """
        try:
            self.cursor.execute("""
                SELECT DISTINCT COALESCE(p1.series_suffix, ''),
                       (SELECT filename FROM playback p2 
                        WHERE p2.series_prefix = p1.series_prefix 
                          AND COALESCE(p2.series_suffix, '') = COALESCE(p1.series_suffix, '')
                        ORDER BY rowid DESC LIMIT 1) as last_filename,
                       (SELECT MAX(percent) FROM playback p3 
                        WHERE p3.series_prefix = p1.series_prefix 
                          AND COALESCE(p3.series_suffix, '') = COALESCE(p1.series_suffix, '')) as max_percent
                FROM playback p1
                WHERE p1.series_prefix = ? 
                  AND COALESCE(p1.series_suffix, '') != COALESCE(?, '')
            """, (series_prefix, current_suffix))
            
            return self.cursor.fetchall()
        except sqlite3.Error as e:
            print(f"Ошибка поиска версий: {e}", file=sys.stderr)
            return []
    
    def get_playback_batch(self, directory: str, filenames: List[str]) -> Dict[str, int]:
        """Пакетное получение процентов просмотра для списка файлов
        
        Возвращает: словарь {filename: percent}
        Оптимизация: один SQL запрос вместо N запросов
        """
        if not filenames:
            return {}
        
        try:
            # Формируем полные пути
            full_paths = [f"{directory}/{filename}" for filename in filenames]
            
            # Создаём плейсхолдеры для IN запроса
            placeholders = ','.join(['?'] * len(full_paths))
            
            query = f"""
                SELECT filename, percent 
                FROM playback 
                WHERE filename IN ({placeholders})
            """
            
            self.cursor.execute(query, full_paths)
            
            # Преобразуем в словарь: basename -> percent
            result = {}
            for full_path, percent in self.cursor.fetchall():
                basename = full_path.split('/')[-1]
                result[basename] = percent
            
            # Для файлов без записи в БД возвращаем 0
            for filename in filenames:
                if filename not in result:
                    result[filename] = 0
            
            return result
        except sqlite3.Error as e:
            print(f"Ошибка пакетного получения: {e}", file=sys.stderr)
            return {filename: 0 for filename in filenames}


# ============================================================================
# CLI ИНТЕРФЕЙС
# ============================================================================

def cli_init_db():
    """CLI: Инициализация БД"""
    with VlcDatabase() as db:
        success = db.init_db()
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_save_playback(args: List[str]):
    """CLI: Сохранение прогресса воспроизведения
    
    Аргументы: filename position duration percent [series_prefix] [series_suffix]
    """
    if len(args) < 4:
        print("ERROR: Недостаточно аргументов", file=sys.stderr)
        return 1
    
    filename = args[0]
    position = int(args[1])
    duration = int(args[2])
    percent = int(args[3])
    series_prefix = args[4] if len(args) > 4 and args[4] else None
    series_suffix = args[5] if len(args) > 5 and args[5] else None
    
    with VlcDatabase() as db:
        success = db.save_playback(filename, position, duration, percent, 
                                   series_prefix, series_suffix)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_get_playback(args: List[str]):
    """CLI: Получение данных воспроизведения
    
    Аргументы: filename
    Вывод: position|duration|percent|series_prefix|series_suffix
    """
    if len(args) < 1:
        print("ERROR: Укажите filename", file=sys.stderr)
        return 1
    
    filename = args[0]
    
    with VlcDatabase() as db:
        result = db.get_playback(filename)
        if result:
            print("|".join(map(str, result)))
            return 0
        else:
            return 1


def cli_get_playback_percent(args: List[str]):
    """CLI: Получение процента просмотра
    
    Аргументы: filename
    Вывод: percent
    """
    if len(args) < 1:
        print("ERROR: Укажите filename", file=sys.stderr)
        return 1
    
    filename = args[0]
    
    with VlcDatabase() as db:
        percent = db.get_playback_percent(filename)
        print(percent)
        return 0


def cli_save_series_settings(args: List[str]):
    """CLI: Сохранение настроек сериала
    
    Аргументы: series_prefix series_suffix autoplay skip_intro skip_outro 
               [intro_start] [intro_end] [outro_start]
    """
    if len(args) < 5:
        print("ERROR: Недостаточно аргументов", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    autoplay = int(args[2])
    skip_intro = int(args[3])
    skip_outro = int(args[4])
    intro_start = int(args[5]) if len(args) > 5 and args[5] else None
    intro_end = int(args[6]) if len(args) > 6 and args[6] else None
    outro_start = int(args[7]) if len(args) > 7 and args[7] else None
    
    with VlcDatabase() as db:
        success = db.save_series_settings(series_prefix, series_suffix, 
                                         autoplay, skip_intro, skip_outro,
                                         intro_start, intro_end, outro_start)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_get_series_settings(args: List[str]):
    """CLI: Получение настроек сериала
    
    Аргументы: series_prefix series_suffix
    Вывод: autoplay|skip_intro|skip_outro|intro_start|intro_end|outro_start
    """
    if len(args) < 2:
        print("ERROR: Укажите series_prefix и series_suffix", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    
    with VlcDatabase() as db:
        result = db.get_series_settings(series_prefix, series_suffix)
        if result:
            print("|".join(map(str, result)))
            return 0
        else:
            return 1


def cli_series_settings_exist(args: List[str]):
    """CLI: Проверка существования настроек
    
    Аргументы: series_prefix series_suffix
    Вывод: 1 (существуют) или 0 (не существуют)
    """
    if len(args) < 2:
        print("ERROR: Укажите series_prefix и series_suffix", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    
    with VlcDatabase() as db:
        exists = db.series_settings_exist(series_prefix, series_suffix)
        print("1" if exists else "0")
        return 0


def cli_find_other_versions(args: List[str]):
    """CLI: Поиск других версий сериала
    
    Аргументы: series_prefix current_suffix
    Вывод: suffix|last_filename|max_percent (по строке на версию)
    """
    if len(args) < 2:
        print("ERROR: Укажите series_prefix и current_suffix", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    current_suffix = args[1]
    
    with VlcDatabase() as db:
        results = db.find_other_versions(series_prefix, current_suffix)
        for row in results:
            print("|".join(map(str, row)))
        return 0


def cli_get_playback_batch(args: List[str]):
    """CLI: Пакетное получение процентов для списка файлов
    
    Аргументы: directory filename1 filename2 ... filenameN
    Вывод: filename:percent (по строке на файл)
    """
    if len(args) < 2:
        print("ERROR: Укажите directory и список файлов", file=sys.stderr)
        return 1
    
    directory = args[0]
    filenames = args[1:]
    
    with VlcDatabase() as db:
        results = db.get_playback_batch(directory, filenames)
        for filename, percent in results.items():
            print(f"{filename}:{percent}")
        return 0


def print_usage():
    """Вывод справки по использованию"""
    print("""
Использование: vlc_db.py <команда> [аргументы]

Команды:
  init                                    - Инициализация БД
  save_playback <file> <pos> <dur> <%> [prefix] [suffix] - Сохранить прогресс
  get_playback <file>                     - Получить прогресс
  get_percent <file>                      - Получить процент
  get_batch <dir> <file1> [file2] ...     - Пакетное получение процентов
  save_settings <prefix> <suffix> <auto> <intro> <outro> [i_start] [i_end] [o_start]
  get_settings <prefix> <suffix>          - Получить настройки
  settings_exist <prefix> <suffix>        - Проверить настройки
  find_versions <prefix> <suffix>         - Найти другие версии

Примеры:
  vlc_db.py init
  vlc_db.py save_playback "video.mkv" 120 3600 3 "Show.S01" "1080p.mkv"
  vlc_db.py get_playback "video.mkv"
  vlc_db.py get_percent "video.mkv"
  vlc_db.py get_batch "/path/to/dir" "video1.mkv" "video2.mkv" "video3.mkv"
""")


def main():
    """Главная функция CLI"""
    if len(sys.argv) < 2:
        print_usage()
        return 1
    
    command = sys.argv[1]
    args = sys.argv[2:]
    
    commands = {
        'init': lambda: cli_init_db(),
        'save_playback': lambda: cli_save_playback(args),
        'get_playback': lambda: cli_get_playback(args),
        'get_percent': lambda: cli_get_playback_percent(args),
        'get_batch': lambda: cli_get_playback_batch(args),
        'save_settings': lambda: cli_save_series_settings(args),
        'get_settings': lambda: cli_get_series_settings(args),
        'settings_exist': lambda: cli_series_settings_exist(args),
        'find_versions': lambda: cli_find_other_versions(args),
    }
    
    if command in commands:
        return commands[command]()
    else:
        print(f"ERROR: Неизвестная команда '{command}'", file=sys.stderr)
        print_usage()
        return 1


if __name__ == "__main__":
    sys.exit(main())
