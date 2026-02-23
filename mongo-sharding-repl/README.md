# mongo-sharding-repl

MongoDB шардирование с 2 шардами и репликацией (по 3 ноды в каждом replica set).

## Запуск

```bash
docker compose up -d
```

## Инициализация

```bash
./scripts/init-repl.sh
```

Инициализирует 3 replica set'а (config_rs, shard1_rs, shard2_rs) по 3 ноды в каждом, добавляет шарды в кластер, включает шардирование коллекции `somedb.helloDoc` по hashed `_id`, вставляет 1000 тестовых документов.

## Тестирование

```bash
./scripts/test-repl.sh
```

Выводит общее количество документов и распределение по шардам.

Также можно открыть http://localhost:8080 — приложение покажет информацию о топологии, шардах с репликами и количество документов.

## Остановка и очистка

```bash
./scripts/delete-repl.sh
```

Останавливает контейнеры и удаляет volumes (`docker compose down -v`).
