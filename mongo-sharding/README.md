# mongo-sharding

MongoDB шардирование с 2 шардами.

## Запуск

```bash
docker compose up -d
```

## Инициализация шардирования

```bash
./scripts/init-sharding.sh
```

Инициализирует replica sets, добавляет шарды в кластер, включает шардирование коллекции `somedb.helloDoc` по hashed `_id`, вставляет 1000 тестовых документов.

## Тестирование

```bash
./scripts/test-sharding.sh
```

Выводит общее количество документов и распределение по шардам.

Также можно открыть http://localhost:8080 — приложение покажет общее количество документов и распределение по шардам.

## Остановка и очистка

```bash
./scripts/delete-sharding.sh
```

Останавливает контейнеры и удаляет volumes (`docker compose down -v`).
