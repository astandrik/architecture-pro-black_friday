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
sh.enableSharding("mobilnyi_mir") // legacy, turned on by default in mongo 6.0+
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

### 9.1.1 Контекст инфраструктуры

Кластер из заданий 3-4: 2 шарда × 3 ноды (1 primary + 2 secondary), `mongos_router`, Redis-кеш (60 сек TTL). Приложение подключается к `mongos_router:27017`, `readPreference` по умолчанию — `primary`.

### 9.1.2 Основные понятия

**Read Preference** — настройка MongoDB, которая определяет, на какой узел replica set отправляется запрос чтения:
- `primary` — чтение только с primary-узла (самые свежие данные, но вся нагрузка на один узел)
- `secondaryPreferred` — предпочтение secondary-узлам (разгружает primary), с автоматическим fallback на primary, если secondary недоступны

**Read Concern** — настройка MongoDB, определяющая уровень гарантий для прочитанных данных:
- `local` — возвращает данные из локального хранилища узла; быстро, но данные могут быть откачены при failover
- `majority` — возвращает только данные, подтверждённые большинством реплик; медленнее, но гарантирует, что данные не будут откачены

### 9.2 Сводная таблица операций чтения

| Коллекция | Операция | Read Preference | Read Concern | Допустимый лаг | Чтение с secondary? |
|---|---|---|---|---|---|
| `orders` | История заказов клиента | `secondaryPreferred` | `local` | 5-10 сек | Да |
| `orders` | Статус конкретного заказа | `primary` | `majority` | 0 | Только primary |
| `products` | Каталог (категория + цена) | `secondaryPreferred` | `local` | 5-10 сек | Да |
| `products` | Страница товара (описание) | `secondaryPreferred` | `local` | 5-10 сек | Да |
| `products` | Остатки (отображение на странице) | `secondaryPreferred` | `local` | 3-5 сек | Да |
| `products` | Остатки (при оформлении заказа) | `primary` | `majority` | 0 | Только primary |
| `carts` | Получение активной корзины | `primary` | `majority` | 0 | Только primary |
| `carts` | Чтение гостевой корзины при слиянии | `primary` | `majority` | 0 | Только primary |

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

`maxStalenessSeconds` — максимально допустимое отставание secondary от primary. Если secondary отстала дольше порога, драйвер перенаправляет чтение на primary. Минимальное значение — **90 секунд** (ограничение MongoDB для всех типов развёртывания). Задаётся в connection string (`MONGODB_URL` в `compose.yaml`).

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

#### Connection string приложения

В `sharding-repl-cache/compose.yaml` переменная `MONGODB_URL` сейчас:
```
MONGODB_URL: "mongodb://mongos_router:27017"
```

Рекомендуемое значение с настройками чтения с реплик:
```
MONGODB_URL: "mongodb://mongos_router:27017/?readPreference=secondaryPreferred&maxStalenessSeconds=90&readConcernLevel=local"
```

- `readPreference=secondaryPreferred` — чтение по умолчанию идёт на secondary (разгрузка primary)
- `maxStalenessSeconds=90` — если secondary отстала > 90 сек, чтение переключается на primary
- `readConcernLevel=local` — данные из локального хранилища узла (быстро, без гарантии durability)

Операции со строгой консистентностью (статус заказа, остатки при checkout, корзина) переопределяют эти настройки на уровне запроса через API драйвера: `readPreference=primary`, `readConcern=majority`.

#### Per-query override в MongoDB Shell

`.readPref()` задаёт Read Preference, `.readConcern()` — Read Concern. `maxStalenessSeconds` в shell не поддерживается — только из connection string ([документация](https://www.mongodb.com/docs/manual/reference/method/cursor.readPref/)).

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

## Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

### 10.1 Анализ сущностей и выбор данных для миграции

#### Проблема MongoDB при масштабировании

При Black Friday (50 000 запросов/сек) магазин использовал MongoDB с Range-Based Sharding. При добавлении новых шардов MongoDB перераспределяла данные между всеми узлами, что вызвало просадку latency в пик нагрузки.

Cassandra использует consistent hashing: данные распределяются по кольцу хэш-значений, каждый узел отвечает за свой участок. При добавлении 4-го узла в кластер из 3 перемещается ~25% данных (от соседей по кольцу), а не 100%. Каждый физический узел делится на vnodes (256 в Cassandra 3.x, 16 в 4.0+) для равномерного распределения.

#### Оценка сущностей

| Сущность | Масштабируемость | Геораспределённость | Скорость записи | Целостность | Cassandra? |
|---|---|---|---|---|---|
| `orders` | Линейный рост при пиках | Да (геозоны) | Высокая при Black Friday | Транзакция с `products` при создании | Нет |
| `carts` | Пропорциональна трафику | Нет | Каждое действие = запись | Short-lived, TTL | Да |
| `user_sessions` | Пропорциональна трафику | Нет | Создание + heartbeat | Short-lived, TTL | Да |
| `products` | Растёт медленно | Нет | Частые обновления stock | Строгая при checkout | Нет |

#### Сущности для переноса в Cassandra

**carts.** Добавление товара, удаление, изменение количества — каждое действие пользователя порождает запись. Корзины живут 24 часа и удаляются автоматически (TTL на уровне строки). Доступ по `user_id` или `session_id`, сложные запросы не требуются. Корзина — самодостаточная сущность: операции с ней не требуют атомарности с другими коллекциями.

**user_sessions.** Высокий объём записей при пике, TTL 1 час, доступ по `session_id`. При потере сессии — повторный вход.

#### Сущности, остающиеся в MongoDB

**orders** остаётся в MongoDB. Создание заказа требует атомарного списания остатков из `products.stock` — это одна транзакция в MongoDB (`session.startTransaction()`). Если перенести `orders` в Cassandra, а `products` оставить в MongoDB, возникает распределённая транзакция между двумя СУБД. Cassandra не поддерживает multi-row транзакции, поэтому атомарность «создать заказ + уменьшить остаток» невозможна без дополнительного механизма (Saga-паттерн, 2PC). Saga заменяет ACID-транзакцию на eventual consistency: между шагами «создать заказ» и «списать остаток» система несогласована, и параллельный checkout может продать товар, которого уже нет. MongoDB с хэшированным шардированием по `{customer_id: "hashed"}` (задание 7) справляется с нагрузкой на запись заказов.

**products** остаётся в MongoDB. Поиск товаров по категории и диапазону цен (`WHERE category = X AND price BETWEEN Y AND Z`) плохо ложится на Cassandra: такие запросы требуют сканирования нескольких партиций. Обновление остатков (`stock`) требует условных записей и rollback, а Cassandra counters этого не поддерживают. При оформлении заказа нужна строгая консистентность (`readConcern: "majority"` из задания 9). Кроме того, `orders` и `products` участвуют в одной транзакции (см. выше) — обе коллекции должны находиться в одной СУБД.

---

### 10.2 Концептуальная модель данных Cassandra

#### Query-First Design

Модель строится от запросов: один запрос = одна таблица. Корзина авторизованного пользователя и гостевая корзина — два разных паттерна доступа (по `user_id` и по `session_id`), поэтому две таблицы.

#### Keyspace

```cql
CREATE KEYSPACE mobilnyi_mir
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3
};
```

`NetworkTopologyStrategy` размещает реплики в разных стойках внутри датацентра. RF = 3 — каждая запись хранится на 3 узлах в `dc1`. При падении одного узла данные доступны на двух оставшихся.

#### UDT (User Defined Types)

```cql
CREATE TYPE cart_item (
  product_id TEXT,
  quantity INT
);
```

#### Таблица 1: carts_by_user

Назначение: активная корзина авторизованного пользователя.

```cql
CREATE TABLE carts_by_user (
  user_id TEXT,
  status TEXT,
  updated_at TIMESTAMP,
  cart_id UUID,
  items LIST<FROZEN<cart_item>>,
  created_at TIMESTAMP,
  PRIMARY KEY ((user_id), status, updated_at)
) WITH CLUSTERING ORDER BY (status ASC, updated_at DESC)
  AND default_time_to_live = 86400;
```

| Элемент | Значение | Обоснование |
|---|---|---|
| Partition key | `user_id` | Все корзины пользователя на одной партиции |
| Clustering key | `status, updated_at DESC` | Запрос `WHERE user_id = X AND status = 'active'` — кластеризация позволяет отфильтровать по статусу без полного сканирования партиции |
| TTL | 86400 сек (24 часа) | Автоочистка неактивных корзин — Cassandra удаляет записи автоматически |
| Горячие партиции | Нет | У одного пользователя 1-3 корзины (active + abandoned) |

В MongoDB (задание 7) шардирование `carts` по `{user_id: "hashed"}` невозможно: у гостевых корзин `user_id = null`, хэш от null одинаков — все гостевые корзины на одном шарде. Необходимо было использовать `{_id: "hashed"}`.

В Cassandra корзины разнесены по двум таблицам: `carts_by_user` (partition key = `user_id`, всегда заполнен) и `carts_by_session` (partition key = `session_id`, всегда заполнен). Приложение маршрутизирует запрос: авторизованный → `carts_by_user`, гость → `carts_by_session`. Null-значений в partition key нет.

#### Таблица 2: carts_by_session

Назначение: гостевая корзина по `session_id`.

```cql
CREATE TABLE carts_by_session (
  session_id TEXT,
  cart_id UUID,
  items LIST<FROZEN<cart_item>>,
  status TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  PRIMARY KEY ((session_id))
) WITH default_time_to_live = 86400;
```

| Элемент | Значение | Обоснование |
|---|---|---|
| Partition key | `session_id` | Прямой lookup гостевой корзины. Одна сессия = одна корзина |
| TTL | 86400 сек (24 часа) | Гостевые корзины живут недолго; автоочистка без cron-задач |

#### Таблица 3: user_sessions

Назначение: хранение пользовательских сессий.

```cql
CREATE TABLE user_sessions (
  session_id TEXT,
  user_id TEXT,
  created_at TIMESTAMP,
  last_activity TIMESTAMP,
  ip_address TEXT,
  user_agent TEXT,
  PRIMARY KEY ((session_id))
) WITH default_time_to_live = 3600;
```

| Элемент | Значение | Обоснование |
|---|---|---|
| Partition key | `session_id` | Прямой key-value lookup при каждом HTTP-запросе |
| TTL | 3600 сек (1 час) | Сессии истекают автоматически; heartbeat (`last_activity` update) продлевает TTL |

#### Consistent Hashing vs Range-Based Sharding

| Характеристика | MongoDB Range-Based | Cassandra Consistent Hashing |
|---|---|---|
| Добавление узла | Полное перераспределение данных | Перемещается ~1/N данных (от соседа по кольцу) |
| Влияние на latency | Просадка в пик нагрузки | Минимальное — основная масса данных не перемещается |
| Virtual nodes | Нет | vnodes на узел (256 в 3.x, 16 в 4.0+) → данные распределены равномерно |
| Горячие партиции | Зависит от шард-ключа | Партиции распределяются по хэшу partition key |

При Black Friday (50k req/sec) добавление 4-го узла в кластер Cassandra из 3 узлов затронет ~25% данных (по ~8% с каждого из 3 существующих узлов), а не 100% как при Range-Based Sharding в MongoDB.

#### Сводная таблица ключей

| Таблица | Partition key | Clustering key | TTL | Запрос |
|---|---|---|---|---|
| `carts_by_user` | `user_id` | `status, updated_at DESC` | 24h | Корзина авторизованного |
| `carts_by_session` | `session_id` | — | 24h | Гостевая корзина |
| `user_sessions` | `session_id` | — | 1h | Lookup сессии |

---

### 10.3 Стратегии восстановления целостности данных

#### Описание стратегий

| Стратегия | Механизм | Когда срабатывает | Overhead |
|---|---|---|---|
| **Hinted Handoff** | Координатор сохраняет hints для недоступной реплики и отправляет их при восстановлении узла | Кратковременное падение узла (секунды — минуты). Hints хранятся до 3 часов (по умолчанию) | Минимальный: запись hint локально на координаторе |
| **Read Repair** | При чтении координатор сравнивает данные с нескольких реплик; если обнаружена разница — обновляет устаревшие реплики | При каждом чтении (если включено) | Увеличивает latency чтения: вместо 1 реплики опрашиваются все |
| **Anti-Entropy Repair** | Фоновый процесс (`nodetool repair`) сравнивает Merkle trees реплик и синхронизирует расхождения | По расписанию (еженедельно) или после восстановления узла. Должен выполняться минимум раз в `gc_grace_seconds` (по умолчанию 10 дней) | Высокий: ресурсоёмкий процесс, нагружает диск и сеть |

#### Маппинг стратегий на сущности

| Сущность | Hinted Handoff | Read Repair | Anti-Entropy Repair | CL Write | CL Read |
|---|---|---|---|---|---|
| **carts** | Включён | Отключён | Низкий приоритет | `QUORUM` | `QUORUM` |
| **user_sessions** | Включён | Отключён | Не требуется | `ONE` | `ONE` |

#### Обоснование: carts

Hinted Handoff включён — потеря корзины при добавлении товара критична для конверсии. Read Repair отключён — корзина модифицируется при каждом клике, overhead неприемлем. Вместо этого `CL=QUORUM` (запись и чтение подтверждаются 2 из 3 реплик — пересечение множеств гарантирует актуальные данные). Anti-Entropy Repair низкий приоритет: TTL = 24 часа, старые корзины истекают раньше, чем запустится repair.

#### Обоснование: user_sessions

Hinted Handoff включён (минимальный overhead). Read Repair и Anti-Entropy Repair не нужны: TTL = 1 час, сессии истекают раньше, чем потребуется восстановление. `CL=ONE`: потеря сессии = повторный вход (допустимо), latency в приоритете.

#### Consistency Level и компромиссы

| CL | Поведение (RF=3) | Latency | Доступность | Когда использовать |
|---|---|---|---|---|
| `ONE` | Запись/чтение подтверждается 1 репликой | Минимальная | Максимальная (работает при падении 2 из 3 узлов) | `user_sessions` — некритичные данные |
| `QUORUM` | Запись/чтение подтверждается 2 из 3 реплик | Средняя | Высокая (работает при падении 1 из 3 узлов) | `carts` — бизнес-критичные данные |

`CL=QUORUM` при RF=3: `W + R > N` → `2 + 2 > 3` → strong consistency.

#### Сводная таблица рекомендаций

| Сущность | HH | RR | AER | CL W/R | gc_grace_seconds | Обоснование |
|---|---|---|---|---|---|---|
| `carts_by_user` | Да | Нет | При необходимости | QUORUM / QUORUM | 86400 (1 дн.) | TTL-данные; latency критична |
| `carts_by_session` | Да | Нет | При необходимости | QUORUM / QUORUM | 86400 (1 дн.) | TTL-данные; latency критична |
| `user_sessions` | Да | Нет | Нет | ONE / ONE | 7200 (2 ч.) | Некритичные TTL-данные; latency в приоритете |

---

## Альтернатива: YDB

[YDB](https://ydb.tech/) — open-source (Apache 2.0) распределённая SQL СУБД, разработанная Яндексом. Язык запросов — YQL (диалект SQL). SDK для Python (asyncio), Go, Java и других языков ([документация](https://ydb.tech/docs/en/concepts/)).

### Применение к «Мобильному миру»

В текущей архитектуре `orders` и `products` остаются в MongoDB, потому что создание заказа требует атомарного списания остатков — распределённая транзакция между MongoDB и Cassandra невозможна без Saga-паттерна (задание 10). YDB поддерживает распределённые ACID-транзакции с serializable isolation для любого числа таблиц ([документация](https://ydb.tech/docs/en/concepts/transactions)), поэтому все четыре сущности (`orders`, `products`, `carts`, `user_sessions`) размещаются в одной СУБД.

**Шардирование.** Партиции разбиваются автоматически при достижении 2 ГБ или CPU > 50% (проверка каждые ~15 сек), мержатся обратно при снижении нагрузки ([документация](https://ydb.tech/docs/en/troubleshooting/performance/schemas/splits-merges)). Ручной выбор шард-ключей (задание 7) и мониторинг горячих шардов (задание 8) не требуются.

**Транзакции.** Транзакция «создать заказ + списать остаток» выполняется в одной СУБД без Saga-паттерна. При конфликте (два клиента покупают последний товар) YDB откатывает одну из транзакций (optimistic concurrency control) — overselling невозможен.

**Консистентность.** Serializable isolation по умолчанию. Ручная настройка `readConcern` / `readPreference` (задание 9) и Cassandra CL (задание 10) не нужна. При необходимости снижения latency отдельные запросы переключаются на stale reads.

**TTL.** Автоматическое удаление строк по колонке-таймстампу (`expires_at`). Фоновый процесс BRO, интервал от 15 минут ([документация](https://ydb.tech/docs/en/concepts/ttl)). Для корзин (24ч) и сессий (1ч) достаточно.

**Вторичные индексы.** Синхронные вторичные индексы обновляются в одной транзакции с основной таблицей ([документация](https://ydb.tech/docs/en/concepts/secondary_indexes)). Запрос каталога (`category + price`) выполняется по индексу, а не scatter-gather по шардам.

**Отказоустойчивость.** Два режима: `mirror-3-dc` (3 зоны доступности, переживает падение целой зоны) и `block-4-2` (erasure coding, 8+ серверов в одном ДЦ, переживает падение 2 серверов) ([документация](https://ydb.tech/docs/en/concepts/topology)).

### Сравнение с текущей архитектурой

| Аспект | MongoDB + Cassandra + Redis | YDB + Redis |
|---|---|---|
| Количество СУБД | 3 | 2 |
| Шардирование | Ручной выбор шард-ключей + мониторинг горячих шардов | Автоматический split/merge по размеру и нагрузке |
| Транзакции | MongoDB: multi-document. Cassandra: нет | Распределённые ACID (serializable) |
| Консистентность | Ручная настройка `readConcern` / CL | Строгая по умолчанию |
| TTL | MongoDB: ~60 сек. Cassandra: per-row | BRO: от 15 мин |
| Модель данных | Документная + денормализованная | Реляционная + `JsonDocument` |
| Масштабирование при пиках | `reshardCollection`, `moveRange` | Автоматический split при CPU > 50% |
| Экосистема | MongoDB, Cassandra — широко распространены | Open-source с 2022, активное развитие |

### Ограничения

- **Реляционная модель.** Вложенные структуры (массив `items` внутри заказа) нормализуются в отдельную таблицу `order_items` или хранятся как `JsonDocument` (с потерей типизации и индексации по полям)
- **TTL.** BRO запускается с интервалом от 15 минут — менее точно, чем Cassandra per-row TTL. Для корзин (24ч) и сессий (1ч) допустимо
- **Redis.** YDB не in-memory СУБД. Для кеширования ответов API с latency < 1 мс Redis остаётся в архитектуре
- **Экосистема.** YDB менее распространена за пределами Яндекса, хотя имеет SDK для основных языков

YDB заменяет связку MongoDB + Cassandra одной СУБД. Компромисс — переход от документной модели к реляционной и менее точный TTL. Redis остаётся для кеша.
