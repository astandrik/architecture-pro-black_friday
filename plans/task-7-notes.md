# Задание 7 — Заметки по проектированию шард-ключей

## Коллекция `orders` — РЕШЕНО

### Схема документа

```json
{
  "_id": ObjectId,
  "order_id": String,
  "customer_id": String,
  "order_date": ISODate,
  "items": [
    { "product_id": String, "name": String, "quantity": Int32, "price": Decimal128 }
  ],
  "status": String,       // "pending" | "confirmed" | "shipped" | "delivered" | "cancelled"
  "total": Decimal128,
  "geo_zone": String      // "moscow" | "spb" | "ekb" | "kaliningrad" | ...
}
```

### Основные операции

1. Быстрое создание заказов (write) — по `customer_id`
2. Поиск истории заказов клиента (read) — по `customer_id`
3. Отображение статуса заказа (read) — по `order_id`

### Рассмотренные кандидаты

| Кандидат | Стратегия | Вердикт |
|---|---|---|
| `{order_id: "hashed"}` | Hashed | ❌ История клиента → scatter-gather |
| `{customer_id: "hashed"}` | Hashed | ✅ **ВЫБРАН** — targeted история + равномерное распределение |
| `{geo_zone: 1}` | Range/Zone | ❌ Низкая кардинальность, неравномерное распределение |
| `{geo_zone: 1, customer_id: 1}` | Range + Zone Sharding | ❌ При Black Friday 70% нагрузки на Москву → горячий шард |
| `{customer_id: 1, order_date: -1}` | Range compound | ⚠️ Монотонный рост date → hot spot на запись |

### Итоговый выбор

**Shard key:** `{customer_id: "hashed"}`
**Стратегия:** Hashed Sharding

### Обоснование

- Равномерное распределение записей при пиковой нагрузке (Black Friday)
- Targeted query для самой частой операции чтения (история заказов по customer_id)
- Высокая кардинальность → нет горячих шардов
- `geo_zone` — бизнес-атрибут для аналитики/доставки, не shard key
- Геошардинг отклонён: централизованный кластер, нет региональных серверов, неравномерное распределение по регионам

---

## Коллекция `products` — РЕШЕНО

### Схема документа

```json
{
  "_id": ObjectId,
  "product_id": String,
  "name": String,
  "category": String,        // "electronics" | "audio" | "appliances" | ...
  "price": Decimal128,
  "stock": {                  // остаток по геозонам (вложенный объект!)
    "moscow": Int32,
    "spb": Int32,
    "ekb": Int32,
    "kaliningrad": Int32
  },
  "attributes": {
    "color": String,
    "size": String
  }
}
```

### Основные операции

1. Обновление остатков при покупке (write) — по `product_id`
2. Поиск по категории + фильтр по цене (read) — по `category` + `price` range
3. Страница товара (read) — по `product_id`

### Рассмотренные кандидаты

| Кандидат | Стратегия | Вердикт |
|---|---|---|
| `{product_id: "hashed"}` | Hashed | ✅ **ВЫБРАН** — targeted write/read по product_id, равномерное распределение |
| `{category: 1, product_id: 1}` | Range compound | ❌ 70% товаров = «Электроника» → горячий шард (проблема задания 8) |
| `{category: "hashed"}` | Hashed | ❌ Низкая кардинальность (~10-20 значений) |
| `{price: 1}` | Range | ❌ Мутабельность цены → миграция документа между шардами |
| Геошардинг | Zone Sharding | ❌ Не применим — stock по геозонам = вложенный объект в одном документе, не отдельные документы |

### Итоговый выбор

**Shard key:** `{product_id: "hashed"}`
**Стратегия:** Hashed Sharding

### Обоснование

- Самая частая write-операция (обновление остатков) → targeted на 1 шард
- Страница товара (по product_id) → targeted query
- Нет горячих шардов — Electronics равномерно распределена по всем шардам
- Каталог по категории → scatter-gather, компенсируется вторичным индексом {category: 1, price: 1}
- Геошардинг не применим: stock — вложенный объект, товар нужен всем регионам
- Прямая связь с заданием 8: правильный shard key предотвращает горячий шард

---

## Коллекция `carts` — РЕШЕНО

### Схема документа

```json
{
  "_id": ObjectId,
  "user_id": String,          // null для гостей
  "session_id": String,       // для гостевых корзин
  "items": [
    { "product_id": String, "quantity": Int32 }
  ],
  "status": String,           // "active" | "ordered" | "abandoned"
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate       // TTL — автоматическая очистка
}
```

### Основные операции

1. Создание корзины (write)
2. Получение активной корзины (read) — по `{user_id, status: "active"}` или `{session_id, status: "active"}`
3. Добавить/удалить товар (write) — по `_id`
4. Слияние гостевой → пользовательской (read+write) — `session_id` → `user_id`
5. Пометить как заказанную (write) — по `_id`

### Рассмотренные кандидаты

| Кандидат | Стратегия | Вердикт |
|---|---|---|
| `{_id: "hashed"}` | Hashed | ✅ **ВЫБРАН** — равномерное, нет null-проблемы, targeted по _id |
| `{user_id: "hashed"}` | Hashed | ❌ Гостевые корзины: user_id=null → все на одном шарде → hot spot |
| `{session_id: "hashed"}` | Hashed | ❌ Авторизованные без session_id → та же проблема с null |
| Синтетический `{owner_key: "hashed"}` | Hashed | ⚠️ Хорошая идея, но требует изменения приложения |

### Итоговый выбор

**Shard key:** `{_id: "hashed"}`
**Стратегия:** Hashed Sharding

### Обоснование

- Нет проблемы с null-значениями (у каждого документа уникальный `_id`)
- Равномерное распределение (ObjectId уникален)
- Частые операции (добавить/удалить товар, обновить корзину) идут по `_id` → targeted
- Корзины — временные объекты с TTL → объём данных невелик → scatter-gather приемлем
- Компенсация scatter-gather: вторичные индексы `{user_id: 1, status: 1}` и `{session_id: 1, status: 1}`
- TTL-индекс на `expires_at` для автоматической очистки

---

## Сводная таблица

| Коллекция | Shard Key | Стратегия | Targeted операции | Scatter-Gather операции |
|---|---|---|---|---|
| `orders` | `{customer_id: "hashed"}` | Hashed | История клиента, создание заказа | Поиск по order_id без customer_id |
| `products` | `{product_id: "hashed"}` | Hashed | Страница товара, обновление stock | Каталог по категории + цене |
| `carts` | `{_id: "hashed"}` | Hashed | CRUD по _id корзины | Поиск активной корзины по user_id/session_id |
