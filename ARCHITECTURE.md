# Архитектурный документ: Онлайн-магазин «Мобильный мир»

---

## Задание 7. Проектирование схем коллекций для шардирования данных

### 7.1 Коллекция `orders`

#### Схема документа

```json
{
  "_id": "ObjectId",
  "order_id": "String (уникальный идентификатор заказа)",
  "customer_id": "String (идентификатор клиента)",
  "order_date": "ISODate (дата и время оформления)",
  "items": [
    {
      "product_id": "String",
      "name": "String",
      "quantity": "Int32",
      "price": "Decimal128"
    }
  ],
  "status": "String (pending | confirmed | shipped | delivered | cancelled)",
  "total": "Decimal128 (общая сумма заказа)",
  "geo_zone": "String (геозона заказа: moscow | spb | ekb | kaliningrad | ...)"
}
```

#### Основные операции

| Операция | Тип | Поля поиска |
|---|---|---|
| Быстрое создание заказа | Write | `customer_id` |
| Поиск истории заказов клиента | Read | `customer_id` |
| Отображение статуса заказа | Read | `order_id` |

#### Анализ кандидатов для шард-ключа

| Кандидат | Стратегия | Уникальных значений | Распределение | Запрос к одному шарду | Проблемы |
|---|---|---|---|---|---|
| `{order_id: "hashed"}` | Хэшированная | Много | Равномерное | По `order_id` | История клиента → запрос ко всем шардам |
| `{customer_id: "hashed"}` | Хэшированная | Много | Равномерное | По `customer_id` | Поиск по `order_id` → запрос ко всем шардам |
| `{geo_zone: 1}` | Диапазонная / Зонная | Мало (5-10 зон) | Неравномерное | По `geo_zone` | Москва = 60%+ заказов → горячий шард |
| `{geo_zone: 1, customer_id: 1}` | Составная диапазонная + зонная | Среднее | Неравномерное | По `geo_zone` + `customer_id` | Неравномерное распределение по регионам; при Black Friday Москва перегружена |
| `{customer_id: 1, order_date: -1}` | Составная диапазонная | Много | Умеренное | По `customer_id` + диапазон по дате | `order_date` постоянно растёт → новые записи всегда идут на последний шард |

#### Выбранная стратегия

Шард-ключ: `{customer_id: "hashed"}`

Стратегия: хэшированное шардирование

#### Обоснование

Хэш от `customer_id` равномерно распределяет заказы по шардам — при Black Friday нагрузка делится поровну. Самый частый запрос (история заказов клиента) идёт на один шард, потому что все заказы одного клиента лежат вместе. Поиск по `order_id` без `customer_id` потребует опроса всех шардов, но это решается передачей `customer_id` на уровне приложения.

#### Команды MongoDB

```javascript
sh.enableSharding("mobilnyi_mir")
db.orders.createIndex({ customer_id: "hashed" })
sh.shardCollection("mobilnyi_mir.orders", { customer_id: "hashed" })

// Дополнительные индексы для частых запросов
db.orders.createIndex({ customer_id: 1, order_date: -1 })
db.orders.createIndex({ order_id: 1 }, { unique: true })
db.orders.createIndex({ status: 1 })
```

---

### 7.2 Коллекция `products`

#### Схема документа

```json
{
  "_id": "ObjectId",
  "product_id": "String (уникальный идентификатор товара)",
  "name": "String (наименование)",
  "category": "String (electronics | audio | appliances | books | ...)",
  "price": "Decimal128 (цена)",
  "stock": {
    "moscow": "Int32 (остаток в Москве)",
    "spb": "Int32 (остаток в СПб)",
    "ekb": "Int32 (остаток в Екатеринбурге)",
    "kaliningrad": "Int32 (остаток в Калининграде)"
  },
  "attributes": {
    "color": "String",
    "size": "String"
  }
}
```

#### Основные операции

| Операция | Тип | Поля поиска |
|---|---|---|
| Обновление остатков при покупке | Write | `product_id`, `stock.<geo_zone>` |
| Поиск по категории + фильтр по цене | Read | `category`, `price` |
| Страница товара (описание) | Read | `product_id` |

#### Анализ кандидатов для шард-ключа

| Кандидат | Стратегия | Уникальных значений | Распределение | Запрос к одному шарду | Проблемы |
|---|---|---|---|---|---|
| `{product_id: "hashed"}` | Хэшированная | Много | Равномерное | По `product_id` | Каталог по категории → запрос ко всем шардам |
| `{category: 1, product_id: 1}` | Составная диапазонная | Мало у `category` | Неравномерное | По `category` | 70% товаров — «Электроника» → горячий шард (проблема задания 8) |
| `{category: "hashed"}` | Хэшированная | Мало (10-20 категорий) | Плохое | — | Мало уникальных значений → неравномерные куски данных |
| `{price: 1}` | Диапазонная | Много | Неравномерное | По диапазону цен | Цена может меняться → документ придётся перемещать между шардами |

#### Выбранная стратегия

Шард-ключ: `{product_id: "hashed"}`

Стратегия: хэшированное шардирование

#### Обоснование

70% запросов приходится на категорию «Электроника» (из задания 8). Если шардировать по `category`, эти товары окажутся на одном шарде — получится горячий шард. Хэш от `product_id` распределяет товары равномерно, и обновление остатков / открытие страницы товара идёт на один шард. Поиск по каталогу (`category` + `price`) опрашивает все шарды, но составной индекс `{category: 1, price: 1}` ускоряет поиск внутри каждого из них.

#### Команды MongoDB

```javascript
db.products.createIndex({ product_id: "hashed" })
sh.shardCollection("mobilnyi_mir.products", { product_id: "hashed" })

// Дополнительные индексы для частых запросов
db.products.createIndex({ category: 1, price: 1 })
db.products.createIndex({ product_id: 1 }, { unique: true })
```

---

### 7.3 Коллекция `carts`

#### Схема документа

```json
{
  "_id": "ObjectId",
  "user_id": "String | null (идентификатор пользователя, null для гостей)",
  "session_id": "String (идентификатор сессии для гостевых корзин)",
  "items": [
    {
      "product_id": "String",
      "quantity": "Int32"
    }
  ],
  "status": "String (active | ordered | abandoned)",
  "created_at": "ISODate",
  "updated_at": "ISODate",
  "expires_at": "ISODate (TTL — автоматическая очистка старых корзин)"
}
```

#### Основные операции

| Операция | Тип | Поля поиска |
|---|---|---|
| Создание корзины | Write | Новый документ |
| Получение активной корзины | Read | `{user_id, status: "active"}` или `{session_id, status: "active"}` |
| Добавление/удаление товара | Write | `_id` |
| Слияние гостевой → пользовательской | Read + Write | `session_id` → `user_id` |
| Отметка корзины как заказанной | Write | `_id` |

#### Анализ кандидатов для шард-ключа

| Кандидат | Стратегия | Уникальных значений | Распределение | Запрос к одному шарду | Проблемы |
|---|---|---|---|---|---|
| `{_id: "hashed"}` | Хэшированная | Много | Равномерное | По `_id` | Поиск по `user_id`/`session_id` → запрос ко всем шардам |
| `{user_id: "hashed"}` | Хэшированная | Много | Неравномерное | По `user_id` | Гостевые корзины: `user_id = null` → все на одном шарде → горячий шард |
| `{session_id: "hashed"}` | Хэшированная | Много | Неравномерное | По `session_id` | Авторизованные без `session_id` → `null` → горячий шард |
| `{user_id: 1, session_id: 1}` | Составная диапазонная | Много | Неравномерное | Смешанное | Null-значения в ключе → непредсказуемое распределение |

Проблема null-значений: корзины принадлежат либо авторизованному пользователю (`user_id`), либо гостю (`session_id`). Ни одно из этих полей не заполнено у всех документов: у гостей `user_id = null`, у авторизованных может не быть `session_id`. Хэш от `null` одинаков для всех таких документов — все они попадают на один шард.

#### Выбранная стратегия

Шард-ключ: `{_id: "hashed"}`

Стратегия: хэшированное шардирование

#### Обоснование

У каждого документа свой уникальный `_id`, поэтому проблема с null-значениями не возникает и данные распределяются равномерно. Операции с конкретной корзиной (добавить товар, оформить заказ) идут по `_id` — на один шард. Поиск активной корзины по `user_id` или `session_id` опрашивает все шарды, но корзины временные (TTL), их немного, а составные индексы `{user_id: 1, status: 1}` и `{session_id: 1, status: 1}` ускоряют поиск.

#### Команды MongoDB

```javascript
sh.shardCollection("mobilnyi_mir.carts", { _id: "hashed" })

// Дополнительные индексы для частых запросов
db.carts.createIndex({ user_id: 1, status: 1 })
db.carts.createIndex({ session_id: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

---

### 7.4 Сводная таблица решений

| Коллекция | Шард-ключ | Стратегия | Запрос к одному шарду | Запрос ко всем шардам |
|---|---|---|---|---|
| `orders` | `{customer_id: "hashed"}` | Хэшированная | История заказов по клиенту, создание заказа | Поиск по `order_id` без `customer_id` |
| `products` | `{product_id: "hashed"}` | Хэшированная | Страница товара, обновление остатков | Каталог по категории + цене |
| `carts` | `{_id: "hashed"}` | Хэшированная | Операции с конкретной корзиной | Поиск активной корзины по `user_id`/`session_id` |

Для всех трёх коллекций выбрано хэшированное шардирование. Главная задача «Мобильного мира» — равномерно распределить нагрузку при пиковом трафике (Black Friday). Хэшированное шардирование лучше всего подходит для этого: оно распределяет записи равномерно и не создаёт горячих шардов.

---

## Задание 8. Выявление и устранение «горячих» шардов

### 8.1 Ситуация

Коллекция `products` была шардирована по `{category: 1}`. 70% запросов приходится на категорию «Электроника» — все эти товары оказались на одном шарде, который перегружен.

### 8.2 Метрики для отслеживания состояния шардов

#### Распределение данных

```javascript
db.products.getShardDistribution()
sh.status()
```

Если `getShardDistribution()` показывает, что на одном шарде в 2+ раза больше документов — данные распределены неравномерно.

#### Нагрузка на шарды

```javascript
db.serverStatus().opcounters
// { insert: N, query: N, update: N, delete: N, ... }
```

Если на одном шарде `query` в 2+ раза больше, чем на другом — перекос нагрузки.

#### Текущие операции

```javascript
db.currentOp({ active: true, secs_running: { $gt: 5 } })
```

Если на одном шарде скапливаются долгие операции — он перегружен.

#### Задержки по шардам (latencyStats)

```javascript
db.products.aggregate([
  { $collStats: { latencyStats: { histograms: true } } }
])
```

Возвращает latency по reads, writes, commands для каждого шарда.

#### Медленные запросы

```javascript
db.setProfilingLevel(1, { slowms: 100 })
db.system.profile.find().sort({ ts: -1 }).limit(5)
```

Профилирование записывает запросы дольше 100 мс. Если на одном шарде их в разы больше — он перегружен.

#### Состояние балансировщика

```javascript
sh.getBalancerState()
db.adminCommand({ balancerCollectionStatus: "mobilnyi_mir.products" })
```

Если балансировщик отключён или застрял — перекос данных не исправляется автоматически.

#### Сводная таблица метрик

| Метрика | Команда | Горячий шард, если... |
|---|---|---|
| Количество документов | `getShardDistribution()` | Разница между шардами > 50% |
| Количество операций | `serverStatus().opcounters` | Один шард обрабатывает > 2x операций |
| Latency (p50, p95, p99) | `$collStats: { latencyStats }` | Latency на одном шарде > 2x выше |
| Текущие операции | `db.currentOp()` | На одном шарде > 2x активных операций |
| Время ответа | `system.profile` | Один шард > 2x медленнее |
| CPU / RAM / Disk I/O | Системный мониторинг | CPU > 80% на одном шарде при < 40% на других |

### 8.3 Механизмы перераспределения данных

#### Способ 1: Встроенный балансировщик

Балансировщик автоматически перемещает диапазоны данных между шардами. Но если проблема в самом шард-ключе (все данные одной категории = один диапазон), он не может разделить данные внутри одного значения ключа.

```javascript
sh.startBalancer()
sh.getBalancerState()

db.adminCommand({
  configureCollectionBalancing: "mobilnyi_mir.products",
  chunkSize: 128
})

use config
db.settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "02:00", stop: "06:00" } } },
  { upsert: true }
)
```

Помогает, если перекос возник из-за миграций или роста данных, а не из-за самого шард-ключа.

#### Способ 2: Изменение шард-ключа (reshardCollection)

Если шард-ключ выбран неудачно, нужно его поменять:

```javascript
db.adminCommand({
  reshardCollection: "mobilnyi_mir.products",
  key: { product_id: "hashed" }
})
```

Данные перераспределятся по новому ключу `product_id`, и товары одной категории окажутся на разных шардах.

#### Способ 3: Ручное перемещение диапазонов (moveRange)

Если нужно срочно разгрузить шард, можно переместить диапазоны данных вручную. `moveRange` перемещает диапазон с указанной нижней границей шард-ключа на целевой шард:

```javascript
db.adminCommand({
  moveRange: "mobilnyi_mir.products",
  min: { category: "electronics" },
  toShard: "shard2"
})
```

Ограничение: при шард-ключе `{category: 1}` все товары категории «Электроника» имеют одно значение ключа и попадают в один диапазон. Этот диапазон нельзя разбить на части — можно только переместить целиком на другой шард. Это временная мера; для полноценного решения нужен `reshardCollection` (Способ 2).

#### Способ 4: Зонное шардирование для балансировки

Привязка диапазонов шард-ключа к определённым шардам. Применимо к исходному ключу `{category: 1}` (до решардинга на `{product_id: "hashed"}`):

```javascript
sh.addShardToZone("shard1", "hot")
sh.addShardToZone("shard2", "hot")

sh.updateZoneKeyRange("mobilnyi_mir.products",
  { category: "electronics" },
  { category: "electronics\uffff" },
  "hot"
)
```

После решардинга на `{product_id: "hashed"}` зонные диапазоны задаются по хэшированному значению `product_id` (тип `NumberLong`), что менее практично — в этом случае используйте `reshardCollection` (Способ 2).

### 8.4 Обнаружение и порядок действий

MongoDB Exporter + Prometheus собирают метрики из 8.2 с каждого шарда. Grafana отображает дашборд с `opcounters`, `latencyStats` и распределением документов. Alertmanager отправляет алерт дежурному, когда разница `opcounters.query` между шардами превышает 2x или latency p95 на одном шарде > 2x выше остальных. Дежурный инженер получает алерт и действует по следующему плану:

1. Подтвердить горячий шард через `getShardDistribution()` и `serverStatus().opcounters`
2. Если проблема в шард-ключе — оценить новый ключ через `analyzeShardKey`, затем выполнить `reshardCollection`
3. Если нужна срочная разгрузка — переместить диапазоны вручную через `moveRange`
4. Настроить зонное шардирование для предотвращения повторения

```javascript
db.adminCommand({
  analyzeShardKey: "mobilnyi_mir.products",
  key: { product_id: "hashed" }
})
```

---

## Задание 9. Настройка чтения с реплик и консистентность

### 9.1 Контекст инфраструктуры

Кластер из заданий 3-4: 2 шарда × 3 ноды (1 primary + 2 secondary), `mongos_router`, Redis-кеш (60 сек TTL). Приложение подключается к `mongos_router:27017`, `readPreference` по умолчанию — `primary`.

### 9.2 Сводная таблица операций чтения

| Коллекция | Операция | Read Preference | Read Concern | Допустимый лаг | Чтение с secondary? |
|---|---|---|---|---|---|
| `orders` | История заказов клиента | `secondaryPreferred` | `local` | 5-10 сек | ✅ Да |
| `orders` | Статус конкретного заказа | `primary` | `majority` | 0 | ❌ Только primary |
| `products` | Каталог (категория + цена) | `secondaryPreferred` | `local` | 5-10 сек | ✅ Да |
| `products` | Страница товара (описание) | `secondaryPreferred` | `local` | 5-10 сек | ✅ Да |
| `products` | Остатки (отображение на странице) | `secondaryPreferred` | `local` | 3-5 сек | ✅ Да |
| `products` | Остатки (при оформлении заказа) | `primary` | `majority` | 0 | ❌ Только primary |
| `carts` | Получение активной корзины | `primary` | `majority` | 0 | ❌ Только primary |
| `carts` | Чтение гостевой корзины при слиянии | `primary` | `majority` | 0 | ❌ Только primary |

### 9.3 Коллекция `orders`

**История заказов клиента → `secondaryPreferred`.** Данные заказов после создания меняются редко. Targeted query по шард-ключу `{customer_id: "hashed"}` идёт на один шард — secondary этого шарда обслуживает запрос, разгружая primary при пиках.

**Статус конкретного заказа → `primary`.** Пользователь ожидает видеть актуальный статус сразу после оплаты; stale read может спровоцировать повторную оплату. `readConcern: "majority"` защищает от rollback при failover.

### 9.4 Коллекция `products`

**Каталог (категория + цена) → `secondaryPreferred`.** Описания и цены обновляются редко. Scatter-gather по шардам — чтение с secondary каждого шарда распределяет нагрузку при пиках.

**Страница товара → `secondaryPreferred`.** Targeted query по шард-ключу `product_id`, данные статичны.

**Остатки (отображение) → `secondaryPreferred`.** На странице показываются приблизительно («в наличии» / «мало»). Точная проверка — при checkout на primary.

**Остатки (checkout) → `primary`.** Stale read → overselling (продажа несуществующего товара). `readConcern: "majority"` гарантирует, что значение не будет откачено.

### 9.5 Коллекция `carts`

**Активная корзина → `primary`.** Корзина модифицируется при каждом действии; stale read → дубли товаров. Корзин мало (TTL), нагрузка на primary допустима.

**Чтение при слиянии → `primary`.** Read-modify-write операция; stale read → потеря товаров, добавленных перед логином. Выполняется редко.

### 9.6 Допустимая задержка репликации

#### Фактическая задержка

В здоровом кластере с 3 нодами на шард задержка репликации обычно **< 1-2 секунды**.

#### maxStalenessSeconds

Минимальное значение для шардированных кластеров — **90 секунд**. Защищает от чтения с сильно отставших реплик (сетевые проблемы, долгая синхронизация). Если secondary отстала > 90 сек, чтение перенаправляется на primary. Задаётся через connection string:

```
?readPreference=secondaryPreferred&maxStalenessSeconds=90
```

#### Сводная таблица задержек

| Операция | Бизнес-допустимость | maxStalenessSeconds | readConcern | Комментарий |
|---|---|---|---|---|
| История заказов | 5-10 сек | 90 | `local` | Фактический лаг < 2 сек; 90 — защита от деградации |
| Каталог | 5-10 сек | 90 | `local` | Данные каталога обновляются редко |
| Страница товара | 5-10 сек | 90 | `local` | Описания неизменны |
| Остатки (отображение) | 3-5 сек | 90 | `local` | Приблизительные; точная проверка при checkout |
| Статус заказа | 0 | — | `majority` | Критичен для UX и бизнес-процессов |
| Остатки (checkout) | 0 | — | `majority` | Overselling = прямые убытки |
| Корзина (чтение) | 0 | — | `majority` | Активно модифицируемый объект |
| Корзина (слияние) | 0 | — | `majority` | Read-modify-write; потеря данных при stale read |

### 9.7 Примеры конфигурации

#### Connection string приложения (PyMongo / Motor)

```
mongodb://mongos_router:27017/?readPreference=secondaryPreferred&maxStalenessSeconds=90&readConcernLevel=local
```

Задаёт `secondaryPreferred` + `maxStalenessSeconds=90` + `readConcern=local` по умолчанию. Операции, требующие `primary`, переопределяют readPreference на уровне запроса через API драйвера. Параметры `maxStalenessSeconds` и `readConcernLevel` поддерживаются в connection string драйверов, но не в `mongosh` ([документация](https://www.mongodb.com/docs/manual/reference/connection-string-options/)).

#### Per-query override в MongoDB Shell

`cursor.readPref()` в MongoDB Shell принимает только `mode` и `tagSet`, без `maxStalenessSeconds` ([документация](https://www.mongodb.com/docs/manual/reference/method/cursor.readPref/)). `maxStalenessSeconds` задаётся через connection string.

```javascript
// История заказов — secondaryPreferred (maxStalenessSeconds из connection string)
db.orders.find({ customer_id: "cust_123" }).sort({ order_date: -1 })
  .readPref("secondaryPreferred")
  .readConcern("local")

// Статус заказа — override на primary
db.orders.findOne({ order_id: "ord_456" })
  .readPref("primary")
  .readConcern("majority")

// Каталог — secondaryPreferred
db.products.find({ category: "electronics", price: { $gte: 1000, $lte: 5000 } })
  .readPref("secondaryPreferred")
  .readConcern("local")

// Остатки при checkout — override на primary
db.products.findOne({ product_id: "prod_789" }, { stock: 1 })
  .readPref("primary")
  .readConcern("majority")

// Корзина — override на primary
db.carts.findOne({ user_id: "user_123", status: "active" })
  .readPref("primary")
  .readConcern("majority")
```

### 9.8 Взаимодействие с Redis-кешем

Redis-кеш (из задания 4) дополняет стратегию чтения с реплик:

| Уровень | Механизм | Что разгружает |
|---|---|---|
| L1: Redis | Кеш на уровне приложения, TTL 60 сек | Повторные запросы не доходят до MongoDB |
| L2: Secondary reads | `readPreference: secondaryPreferred` | Разгружает primary внутри каждого шарда |
| L3: Primary | `readPreference: primary` | Используется только для критичных операций |

Для операций с `secondaryPreferred` оба уровня кеша работают совместно: первый запрос идёт на secondary, повторные (в пределах TTL) — из Redis. Для операций с `primary` кеширование не применяется.

---

## Задание 10. Миграция на Cassandra

*TODO*
