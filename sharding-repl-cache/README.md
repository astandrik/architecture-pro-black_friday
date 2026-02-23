# sharding-repl-cache

MongoDB шардирование с 2 шардами, репликацией (по 3 ноды в каждом replica set) и кешированием через Redis.

## Запуск

```bash
docker compose up -d
```

## Инициализация

```bash
./scripts/init-cache.sh
```

Инициализирует 3 replica set'а (config_rs, shard1_rs, shard2_rs) по 3 ноды в каждом, добавляет шарды в кластер, включает шардирование коллекции `somedb.helloDoc` по hashed `_id`, вставляет 1000 тестовых документов.

## Тестирование

```bash
./scripts/test-cache.sh
```

Выводит общее количество документов и распределение по шардам.

Также можно открыть http://localhost:8080 — приложение покажет информацию о топологии, шардах с репликами, количество документов и статус кеширования (`cache_enabled: true`).

### Проверка кеширования

Эндпоинт `GET /helloDoc/users` кешируется на 60 секунд. Первый запрос выполняется ~1 сек, повторный — < 100 мс.

```bash
curl -w "\nВремя: %{time_total}s\n" http://localhost:8080/helloDoc/users
curl -w "\nВремя: %{time_total}s\n" http://localhost:8080/helloDoc/users
```

## Остановка и очистка

```bash
./scripts/delete-cache.sh
```

Останавливает контейнеры и удаляет volumes (`docker compose down -v`).
