#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
vlc_db.py - Библиотека для безопасной работы с SQLite БД
Версия: 1.2.0
Дата: 04.12.2025

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
                    status TEXT DEFAULT NULL,
                    series_prefix TEXT DEFAULT NULL,
                    series_suffix TEXT DEFAULT NULL,
                    description TEXT DEFAULT NULL,
                    outro_triggered INTEGER DEFAULT 0
                )
            """)
            
            # Миграция: добавить outro_triggered если колонки нет
            try:
                self.cursor.execute("SELECT outro_triggered FROM playback LIMIT 1")
            except sqlite3.OperationalError:
                self.cursor.execute("""
                    ALTER TABLE playback ADD COLUMN outro_triggered INTEGER DEFAULT 0
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
                    credits_duration INTEGER DEFAULT NULL,
                    description TEXT DEFAULT NULL,
                    PRIMARY KEY (series_prefix, series_suffix)
                )
            """)
            
            # Миграция: переименовать outro_start → credits_duration если нужно
            try:
                self.cursor.execute("SELECT credits_duration FROM series_settings LIMIT 1")
            except sqlite3.OperationalError:
                # Колонка credits_duration не существует
                try:
                    # Проверяем есть ли outro_start
                    self.cursor.execute("SELECT outro_start FROM series_settings LIMIT 1")
                    # Если есть - переименовываем (SQLite не поддерживает RENAME COLUMN до 3.25)
                    # Создаём новую колонку и копируем данные
                    self.cursor.execute("""
                        ALTER TABLE series_settings ADD COLUMN credits_duration INTEGER DEFAULT NULL
                    """)
                    # Для существующих данных outro_start остаётся, но новые будут использовать credits_duration
                except sqlite3.OperationalError:
                    # outro_start тоже нет - просто добавляем credits_duration
                    self.cursor.execute("""
                        ALTER TABLE series_settings ADD COLUMN credits_duration INTEGER DEFAULT NULL
                    """)
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка инициализации БД: {e}", file=sys.stderr)
            return False
    
    @staticmethod
    def _calculate_status(percent: int) -> Optional[str]:
        """Вычисление статуса из процента просмотра
        
        Возвращает:
            'watched' - 90-100%
            'partial' - 1-89%
            None - 0%
        """
        if percent >= 90:
            return 'watched'
        elif percent >= 1:
            return 'partial'
        else:
            return None
    
    def save_playback(self, filename: str, position: int, duration: int, 
                     percent: int, series_prefix: Optional[str] = None, 
                     series_suffix: Optional[str] = None) -> bool:
        """Сохранение прогресса воспроизведения (защита от SQL injection)"""
        try:
            # Автоматически вычисляем статус из процента
            status = self._calculate_status(percent)
            
            self.cursor.execute("""
                INSERT INTO playback (filename, position, duration, percent, status, series_prefix, series_suffix)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(filename) DO UPDATE SET
                    position = ?,
                    duration = ?,
                    percent = ?,
                    status = ?,
                    series_prefix = ?,
                    series_suffix = ?
            """, (filename, position, duration, percent, status, series_prefix, series_suffix,
                  position, duration, percent, status, series_prefix, series_suffix))
            
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
    
    def get_playback_status(self, filename: str) -> Optional[str]:
        """Получение статуса просмотра
        
        Возвращает: status ('watched', 'partial', None)
        """
        try:
            self.cursor.execute("""
                SELECT status FROM playback WHERE filename = ?
            """, (filename,))
            
            result = self.cursor.fetchone()
            return result[0] if result else None
        except sqlite3.Error as e:
            print(f"Ошибка получения status: {e}", file=sys.stderr)
            return None
    
    def get_playback_batch_status(self, directory: str, filenames: List[str]) -> Dict[str, str]:
        """Пакетное получение статусов для списка файлов
        
        Возвращает: словарь {filename: status}
        Оптимизация: один SQL запрос вместо N запросов
        """
        if not filenames:
            return {}
        
        try:
            # Создаём плейсхолдеры для IN запроса
            placeholders = ','.join(['?'] * len(filenames))
            
            query = f"""
                SELECT filename, COALESCE(status, '') as status
                FROM playback 
                WHERE filename IN ({placeholders})
            """
            
            self.cursor.execute(query, filenames)
            
            # Преобразуем в словарь: filename -> status
            result = {}
            for filename, status in self.cursor.fetchall():
                result[filename] = status if status else ''
            
            # Для файлов без записи в БД возвращаем пустую строку
            for filename in filenames:
                if filename not in result:
                    result[filename] = ''
            
            return result
        except sqlite3.Error as e:
            print(f"Ошибка пакетного получения статусов: {e}", file=sys.stderr)
            return {filename: '' for filename in filenames}
    
    def get_outro_triggered(self, filename: str) -> int:
        """Получение флага outro_triggered
        
        Возвращает: 0 или 1 (0 если нет записи)
        """
        try:
            self.cursor.execute("""
                SELECT outro_triggered FROM playback WHERE filename = ?
            """, (filename,))
            
            result = self.cursor.fetchone()
            return result[0] if result else 0
        except sqlite3.Error as e:
            print(f"Ошибка получения outro_triggered: {e}", file=sys.stderr)
            return 0
    
    def set_outro_triggered(self, filename: str, triggered: int) -> bool:
        """Установка флага outro_triggered (0 или 1)
        
        Создаёт запись если её нет
        """
        try:
            self.cursor.execute("""
                INSERT INTO playback (filename, outro_triggered)
                VALUES (?, ?)
                ON CONFLICT(filename) DO UPDATE SET
                    outro_triggered = ?
            """, (filename, triggered, triggered))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка установки outro_triggered: {e}", file=sys.stderr)
            return False
    
    def get_credits_duration(self, series_prefix: str, series_suffix: str) -> Optional[int]:
        """Получение длительности титров
        
        Возвращает: credits_duration в секундах (None если нет записи)
        """
        try:
            self.cursor.execute("""
                SELECT credits_duration FROM series_settings
                WHERE series_prefix = ? AND series_suffix = ?
            """, (series_prefix, series_suffix))
            
            result = self.cursor.fetchone()
            return result[0] if result and result[0] is not None else None
        except sqlite3.Error as e:
            print(f"Ошибка получения credits_duration: {e}", file=sys.stderr)
            return None
    
    def set_credits_duration(self, series_prefix: str, series_suffix: str, duration: int) -> bool:
        """Установка длительности титров
        
        Создаёт запись если её нет или обновляет существующую
        """
        try:
            if duration < 0:
                print("ERROR: Отрицательная длительность недопустима", file=sys.stderr)
                return False
            
            # Если записи нет - создаём с дефолтными значениями
            if not self.series_settings_exist(series_prefix, series_suffix):
                self.cursor.execute("""
                    INSERT INTO series_settings 
                    (series_prefix, series_suffix, autoplay, skip_intro, skip_outro, credits_duration)
                    VALUES (?, ?, 0, 0, 0, ?)
                """, (series_prefix, series_suffix, duration))
            else:
                # Обновляем только credits_duration
                self.cursor.execute("""
                    UPDATE series_settings 
                    SET credits_duration = ?
                    WHERE series_prefix = ? AND series_suffix = ?
                """, (duration, series_prefix, series_suffix))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка установки credits_duration: {e}", file=sys.stderr)
            return False
    
    def save_series_settings(self, series_prefix: str, series_suffix: str,
                            autoplay: bool, skip_intro: bool, skip_outro: bool,
                            intro_start: Optional[int] = None,
                            intro_end: Optional[int] = None,
                            credits_duration: Optional[int] = None) -> bool:
        """Сохранение настроек сериала (защита от SQL injection)"""
        try:
            self.cursor.execute("""
                INSERT INTO series_settings 
                (series_prefix, series_suffix, autoplay, skip_intro, skip_outro, 
                 intro_start, intro_end, credits_duration)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(series_prefix, series_suffix) DO UPDATE SET
                    autoplay = ?,
                    skip_intro = ?,
                    skip_outro = ?,
                    intro_start = ?,
                    intro_end = ?,
                    credits_duration = ?
            """, (series_prefix, series_suffix, autoplay, skip_intro, skip_outro,
                  intro_start, intro_end, credits_duration,
                  autoplay, skip_intro, skip_outro, intro_start, intro_end, credits_duration))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка сохранения настроек сериала: {e}", file=sys.stderr)
            return False
    
    def get_series_settings(self, series_prefix: str, series_suffix: str) -> Optional[Tuple]:
        """Получение настроек сериала
        
        Возвращает: (autoplay, skip_intro, skip_outro, intro_start, intro_end, credits_duration)
        """
        try:
            self.cursor.execute("""
                SELECT autoplay, skip_intro, skip_outro,
                       COALESCE(intro_start, ''), 
                       COALESCE(intro_end, ''), 
                       COALESCE(credits_duration, '')
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
    
    def get_skip_markers(self, series_prefix: str, series_suffix: str) -> Optional[Dict[str, Optional[int]]]:
        """Получение skip markers для сериала
        
        Возвращает: dict {
            'intro_start': int | None,
            'intro_end': int | None,
            'credits_duration': int | None  # Вместо outro_start
        }
        """
        try:
            self.cursor.execute("""
                SELECT intro_start, intro_end, credits_duration
                FROM series_settings
                WHERE series_prefix = ? AND series_suffix = ?
            """, (series_prefix, series_suffix))
            
            result = self.cursor.fetchone()
            if result:
                return {
                    'intro_start': result[0],
                    'intro_end': result[1],
                    'credits_duration': result[2]  # Вместо outro_start
                }
            else:
                return None
        except sqlite3.Error as e:
            print(f"Ошибка получения skip markers: {e}", file=sys.stderr)
            return None
    
    def set_intro_markers(self, series_prefix: str, series_suffix: str, 
                          start: int, end: int) -> bool:
        """Установка маркеров intro (начало и конец)
        
        Обновляет только intro_start и intro_end, оставляя остальные настройки без изменений
        """
        try:
            # Проверяем корректность значений
            if start < 0 or end < 0:
                print("ERROR: Отрицательные значения недопустимы", file=sys.stderr)
                return False
            
            if end <= start:
                print("ERROR: Конец intro должен быть больше начала", file=sys.stderr)
                return False
            
            # Если записи нет - создаём с дефолтными значениями
            if not self.series_settings_exist(series_prefix, series_suffix):
                self.cursor.execute("""
                    INSERT INTO series_settings 
                    (series_prefix, series_suffix, autoplay, skip_intro, skip_outro, intro_start, intro_end)
                    VALUES (?, ?, 0, 0, 0, ?, ?)
                """, (series_prefix, series_suffix, start, end))
            else:
                # Обновляем только intro markers
                self.cursor.execute("""
                    UPDATE series_settings 
                    SET intro_start = ?, intro_end = ?
                    WHERE series_prefix = ? AND series_suffix = ?
                """, (start, end, series_prefix, series_suffix))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка установки intro markers: {e}", file=sys.stderr)
            return False
    
    def set_outro_marker(self, series_prefix: str, series_suffix: str, start: int) -> bool:
        """Установка маркера outro (только начало)
        
        Обновляет только outro_start, оставляя остальные настройки без изменений
        """
        try:
            # Проверяем корректность значений
            if start < 0:
                print("ERROR: Отрицательные значения недопустимы", file=sys.stderr)
                return False
            
            # Если записи нет - создаём с дефолтными значениями
            if not self.series_settings_exist(series_prefix, series_suffix):
                self.cursor.execute("""
                    INSERT INTO series_settings 
                    (series_prefix, series_suffix, autoplay, skip_intro, skip_outro, outro_start)
                    VALUES (?, ?, 0, 0, 0, ?)
                """, (series_prefix, series_suffix, start))
            else:
                # Обновляем только outro marker
                self.cursor.execute("""
                    UPDATE series_settings 
                    SET outro_start = ?
                    WHERE series_prefix = ? AND series_suffix = ?
                """, (start, series_prefix, series_suffix))
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка установки outro marker: {e}", file=sys.stderr)
            return False
    
    def clear_skip_markers(self, series_prefix: str, series_suffix: str, 
                          marker_type: str = 'all') -> bool:
        """Очистка skip markers
        
        Args:
            marker_type: 'intro', 'outro', или 'all'
        """
        try:
            if marker_type == 'intro':
                self.cursor.execute("""
                    UPDATE series_settings 
                    SET intro_start = NULL, intro_end = NULL
                    WHERE series_prefix = ? AND series_suffix = ?
                """, (series_prefix, series_suffix))
            elif marker_type == 'outro':
                self.cursor.execute("""
                    UPDATE series_settings 
                    SET outro_start = NULL
                    WHERE series_prefix = ? AND series_suffix = ?
                """, (series_prefix, series_suffix))
            elif marker_type == 'all':
                self.cursor.execute("""
                    UPDATE series_settings 
                    SET intro_start = NULL, intro_end = NULL, outro_start = NULL
                    WHERE series_prefix = ? AND series_suffix = ?
                """, (series_prefix, series_suffix))
            else:
                print(f"ERROR: Неизвестный тип маркера '{marker_type}'", file=sys.stderr)
                return False
            
            self.conn.commit()
            return True
        except sqlite3.Error as e:
            print(f"Ошибка очистки skip markers: {e}", file=sys.stderr)
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


def cli_get_playback_status(args: List[str]):
    """CLI: Получение статуса просмотра
    
    Аргументы: filename
    Вывод: status (watched/partial/пусто)
    """
    if len(args) < 1:
        print("ERROR: Укажите filename", file=sys.stderr)
        return 1
    
    filename = args[0]
    
    with VlcDatabase() as db:
        status = db.get_playback_status(filename)
        print(status if status else '')
        return 0


def cli_get_playback_batch_status(args: List[str]):
    """CLI: Пакетное получение статусов для списка файлов
    
    Аргументы: directory filename1 filename2 ... filenameN
    Вывод: filename:status (по строке на файл)
    """
    if len(args) < 2:
        print("ERROR: Укажите directory и список файлов", file=sys.stderr)
        return 1
    
    directory = args[0]
    filenames = args[1:]
    
    with VlcDatabase() as db:
        results = db.get_playback_batch_status(directory, filenames)
        for filename, status in results.items():
            print(f"{filename}:{status}")
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
    Вывод: autoplay|skip_intro|skip_outro|intro_start|intro_end|credits_duration
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


def cli_get_skip_markers(args: List[str]):
    """CLI: Получение skip markers
    
    Аргументы: series_prefix series_suffix
    Вывод: JSON {intro_start, intro_end, outro_start}
    """
    if len(args) < 2:
        print("ERROR: Укажите series_prefix и series_suffix", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    
    with VlcDatabase() as db:
        result = db.get_skip_markers(series_prefix, series_suffix)
        if result:
            print(json.dumps(result))
            return 0
        else:
            return 1


def cli_set_intro(args: List[str]):
    """CLI: Установка intro markers
    
    Аргументы: series_prefix series_suffix start end
    """
    if len(args) < 4:
        print("ERROR: Недостаточно аргументов (series_prefix series_suffix start end)", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    
    try:
        start = int(args[2])
        end = int(args[3])
    except ValueError:
        print("ERROR: start и end должны быть числами", file=sys.stderr)
        return 1
    
    with VlcDatabase() as db:
        success = db.set_intro_markers(series_prefix, series_suffix, start, end)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_set_outro(args: List[str]):
    """CLI: Установка outro marker
    
    Аргументы: series_prefix series_suffix start
    """
    if len(args) < 3:
        print("ERROR: Недостаточно аргументов (series_prefix series_suffix start)", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    
    try:
        start = int(args[2])
    except ValueError:
        print("ERROR: start должен быть числом", file=sys.stderr)
        return 1
    
    with VlcDatabase() as db:
        success = db.set_outro_marker(series_prefix, series_suffix, start)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_clear_skip(args: List[str]):
    """CLI: Очистка skip markers
    
    Аргументы: series_prefix series_suffix [marker_type]
    marker_type: intro, outro, all (по умолчанию all)
    """
    if len(args) < 2:
        print("ERROR: Недостаточно аргументов (series_prefix series_suffix [marker_type])", file=sys.stderr)
        return 1
    
    series_prefix = args[0]
    series_suffix = args[1]
    marker_type = args[2] if len(args) > 2 else 'all'
    
    with VlcDatabase() as db:
        success = db.clear_skip_markers(series_prefix, series_suffix, marker_type)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_get_outro_triggered(args: List[str]):
    """Получение outro_triggered флага"""
    if len(args) < 1:
        print("ERROR: Укажите filename", file=sys.stderr)
        return 1
    
    with VlcDatabase() as db:
        triggered = db.get_outro_triggered(args[0])
        print(triggered)
        return 0


def cli_set_outro_triggered(args: List[str]):
    """Установка outro_triggered флага"""
    if len(args) < 2:
        print("ERROR: Укажите filename и triggered (0/1)", file=sys.stderr)
        return 1
    
    try:
        triggered = int(args[1])
        if triggered not in [0, 1]:
            raise ValueError
    except ValueError:
        print("ERROR: triggered должен быть 0 или 1", file=sys.stderr)
        return 1
    
    with VlcDatabase() as db:
        success = db.set_outro_triggered(args[0], triggered)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def cli_get_credits_duration(args: List[str]):
    """Получение credits_duration"""
    if len(args) < 2:
        print("ERROR: Укажите series_prefix и series_suffix", file=sys.stderr)
        return 1
    
    with VlcDatabase() as db:
        duration = db.get_credits_duration(args[0], args[1])
        if duration is not None:
            print(duration)
            return 0
        else:
            return 1


def cli_set_credits_duration(args: List[str]):
    """Установка credits_duration"""
    if len(args) < 3:
        print("ERROR: Укажите series_prefix series_suffix duration", file=sys.stderr)
        return 1
    
    try:
        duration = int(args[2])
    except ValueError:
        print("ERROR: duration должен быть числом", file=sys.stderr)
        return 1
    
    with VlcDatabase() as db:
        success = db.set_credits_duration(args[0], args[1], duration)
        print("OK" if success else "ERROR")
        return 0 if success else 1


def print_usage():
    """Вывод справки по использованию"""
    print("""
Использование: vlc_db.py <команда> [аргументы]

Команды:
  init                                    - Инициализация БД
  save_playback <file> <pos> <dur> <%> [prefix] [suffix] - Сохранить прогресс
  get_playback <file>                     - Получить прогресс
  get_percent <file>                      - Получить процент
  get_status <file>                       - Получить статус
  get_batch <dir> <file1> [file2] ...     - Пакетное получение процентов
  get_batch_status <dir> <file1> [file2] ... - Пакетное получение статусов
  save_settings <prefix> <suffix> <auto> <intro> <outro> [i_start] [i_end] [o_start]
  get_settings <prefix> <suffix>          - Получить настройки
  settings_exist <prefix> <suffix>        - Проверить настройки
  find_versions <prefix> <suffix>         - Найти другие версии
  get-skip-markers <prefix> <suffix>      - Получить skip markers (JSON)
  set-intro <prefix> <suffix> <start> <end> - Установить intro markers
  set-outro <prefix> <suffix> <start>     - Установить outro marker
  clear-skip <prefix> <suffix> [type]     - Очистить markers (intro/outro/all)

Примеры:
  vlc_db.py init
  vlc_db.py save_playback "video.mkv" 120 3600 3 "Show.S01" "1080p.mkv"
  vlc_db.py get_playback "video.mkv"
  vlc_db.py get_percent "video.mkv"
  vlc_db.py get_batch "/path/to/dir" "video1.mkv" "video2.mkv" "video3.mkv"
  vlc_db.py get-skip-markers "Euphoria" "S02"
  vlc_db.py set-intro "Euphoria" "S02" 30 90
  vlc_db.py set-outro "Euphoria" "S02" 3300
  vlc_db.py clear-skip "Euphoria" "S02" intro
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
        'get_status': lambda: cli_get_playback_status(args),
        'get_batch': lambda: cli_get_playback_batch(args),
        'get_batch_status': lambda: cli_get_playback_batch_status(args),
        'save_settings': lambda: cli_save_series_settings(args),
        'get_settings': lambda: cli_get_series_settings(args),
        'settings_exist': lambda: cli_series_settings_exist(args),
        'find_versions': lambda: cli_find_other_versions(args),
        'get-skip-markers': lambda: cli_get_skip_markers(args),
        'set-intro': lambda: cli_set_intro(args),
        'set-outro': lambda: cli_set_outro(args),
        'clear-skip': lambda: cli_clear_skip(args),
        'get-outro-triggered': lambda: cli_get_outro_triggered(args),
        'set-outro-triggered': lambda: cli_set_outro_triggered(args),
        'get-credits-duration': lambda: cli_get_credits_duration(args),
        'set-credits-duration': lambda: cli_set_credits_duration(args),
    }
    
    if command in commands:
        return commands[command]()
    else:
        print(f"ERROR: Неизвестная команда '{command}'", file=sys.stderr)
        print_usage()
        return 1


if __name__ == "__main__":
    sys.exit(main())
