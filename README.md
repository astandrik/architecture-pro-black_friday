# Проектная работа: Онлайн-магазин «Мобильный мир»

Повышение отказоустойчивости и производительности MongoDB — шардирование, репликация, кеширование.

## Структура репозитория

| Директория | Описание |
|---|---|
| `mongo-sharding/` | Задание 2. MongoDB с шардированием (2 шарда) |
| `mongo-sharding-repl/` | Задание 3. Шардирование + репликация (по 3 ноды на шард) |
| `sharding-repl-cache/` | Задание 4. Шардирование + репликация + Redis-кеш |
| `schemas/` | Задания 1, 5, 6. Схемы draw.io (5 этапов) |
| `cdn.drawio` | Итоговая схема (задания 1 + 5 + 6) |
| `ARCHITECTURE.md` | Задания 7–10. Архитектурный документ |

## Запуск финальной версии (sharding-repl-cache)

Для проверки используется директория `sharding-repl-cache/`, которая включает шардирование, репликацию и кеширование.

### 1. Запуск сервисов

```bash
cd sharding-repl-cache
docker compose up -d
```

### 2. Инициализация MongoDB

```bash
./scripts/init-cache.sh
```

Скрипт выполняет:
- Инициализацию replica set конфиг-серверов (`config_rs`: configSrv1, configSrv2, configSrv3)
- Инициализацию replica set шарда 1 (`shard1_rs`: shard1-1, shard1-2, shard1-3)
- Инициализацию replica set шарда 2 (`shard2_rs`: shard2-1, shard2-2, shard2-3)
- Добавление шардов в кластер через `mongos_router`
- Включение шардирования коллекции `somedb.helloDoc` по `{_id: "hashed"}`
- Вставку 1000 тестовых документов

### 3. Проверка

Откройте http://localhost:8080 — приложение отобразит JSON с информацией:
- Топология MongoDB (`mongo_topology_type: "Sharded"`)
- Шарды с репликами (`shards`)
- Количество документов в коллекции (`collections`)
- Статус кеширования (`cache_enabled: true`)

Проверить статус сервисов:

```bash
docker compose ps
```

### 4. Проверка распределения данных по шардам

```bash
./scripts/test-cache.sh
```

### 5. Проверка кеширования

Эндпоинт `GET /helloDoc/users` кешируется на 60 секунд. Первый вызов ~1 сек, повторный < 100 мс:

```bash
curl -w "\nВремя: %{time_total}s\n" http://localhost:8080/helloDoc/users
curl -w "\nВремя: %{time_total}s\n" http://localhost:8080/helloDoc/users
```

### 6. Остановка

```bash
./scripts/delete-cache.sh
```

## Запуск базовой версии (single-node MongoDB)

```bash
docker compose up -d
```

Приложение доступно на http://localhost:8080

## Доступные эндпоинты

Swagger: http://localhost:8080/docs
