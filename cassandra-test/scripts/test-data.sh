#!/bin/bash
set -e

cd "$(dirname "$0")/.."

docker-compose exec -T cassandra-1 nodetool status

docker-compose exec -T cassandra-1 cqlsh <<'EOF'
USE mobilnyi_mir;

INSERT INTO orders_by_customer (customer_id, order_date, order_id, items, status, total, geo_zone)
VALUES (
  'cust_001',
  '2025-11-29T10:00:00Z',
  'ord_1001',
  [{product_id: 'prod_101', name: 'Smartphone X', quantity: 1, price: 49990.00},
   {product_id: 'prod_202', name: 'USB Cable', quantity: 2, price: 590.00}],
  'delivered',
  51170.00,
  'moscow'
);

INSERT INTO orders_by_customer (customer_id, order_date, order_id, items, status, total, geo_zone)
VALUES (
  'cust_001',
  '2025-11-29T14:30:00Z',
  'ord_1002',
  [{product_id: 'prod_303', name: 'Headphones Pro', quantity: 1, price: 12990.00}],
  'shipped',
  12990.00,
  'moscow'
);

INSERT INTO orders_by_customer (customer_id, order_date, order_id, items, status, total, geo_zone)
VALUES (
  'cust_002',
  '2025-11-29T11:15:00Z',
  'ord_1003',
  [{product_id: 'prod_101', name: 'Smartphone X', quantity: 1, price: 49990.00}],
  'pending',
  49990.00,
  'spb'
);

INSERT INTO orders_by_id (order_id, customer_id, order_date, items, status, total, geo_zone)
VALUES (
  'ord_1001',
  'cust_001',
  '2025-11-29T10:00:00Z',
  [{product_id: 'prod_101', name: 'Smartphone X', quantity: 1, price: 49990.00},
   {product_id: 'prod_202', name: 'USB Cable', quantity: 2, price: 590.00}],
  'delivered',
  51170.00,
  'moscow'
);

INSERT INTO orders_by_id (order_id, customer_id, order_date, items, status, total, geo_zone)
VALUES (
  'ord_1002',
  'cust_001',
  '2025-11-29T14:30:00Z',
  [{product_id: 'prod_303', name: 'Headphones Pro', quantity: 1, price: 12990.00}],
  'shipped',
  12990.00,
  'moscow'
);

INSERT INTO orders_by_id (order_id, customer_id, order_date, items, status, total, geo_zone)
VALUES (
  'ord_1003',
  'cust_002',
  '2025-11-29T11:15:00Z',
  [{product_id: 'prod_101', name: 'Smartphone X', quantity: 1, price: 49990.00}],
  'pending',
  49990.00,
  'spb'
);

INSERT INTO carts_by_user (user_id, status, updated_at, cart_id, items, created_at)
VALUES (
  'cust_001',
  'active',
  '2025-11-29T15:00:00Z',
  uuid(),
  [{product_id: 'prod_404', quantity: 3}],
  '2025-11-29T14:50:00Z'
);

INSERT INTO carts_by_session (session_id, cart_id, items, status, created_at, updated_at)
VALUES (
  'sess_abc123',
  uuid(),
  [{product_id: 'prod_101', quantity: 1}, {product_id: 'prod_202', quantity: 2}],
  'active',
  '2025-11-29T15:10:00Z',
  '2025-11-29T15:15:00Z'
);

INSERT INTO user_sessions (session_id, user_id, created_at, last_activity, ip_address, user_agent)
VALUES (
  'sess_xyz789',
  'cust_001',
  '2025-11-29T14:00:00Z',
  '2025-11-29T15:00:00Z',
  '192.168.1.100',
  'Mozilla/5.0'
);

EOF

echo "orders_by_customer (cust_001):"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT order_id, order_date, status, total, geo_zone FROM mobilnyi_mir.orders_by_customer WHERE customer_id = 'cust_001';"

echo "orders_by_id (ord_1001):"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT order_id, status, total FROM mobilnyi_mir.orders_by_id WHERE order_id = 'ord_1001';"

echo "carts_by_user (cust_001, active):"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT user_id, status, cart_id, items FROM mobilnyi_mir.carts_by_user WHERE user_id = 'cust_001' AND status = 'active';"

echo "carts_by_session (sess_abc123):"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT session_id, status, items FROM mobilnyi_mir.carts_by_session WHERE session_id = 'sess_abc123';"

echo "user_sessions (sess_xyz789):"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT session_id, user_id, last_activity FROM mobilnyi_mir.user_sessions WHERE session_id = 'sess_xyz789';"

echo "TTL cart:"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT session_id, TTL(status) as ttl_status FROM mobilnyi_mir.carts_by_session WHERE session_id = 'sess_abc123';"

echo "TTL session:"
docker-compose exec -T cassandra-1 cqlsh -e "SELECT session_id, TTL(user_id) as ttl_user FROM mobilnyi_mir.user_sessions WHERE session_id = 'sess_xyz789';"

echo "QUORUM read:"
docker-compose exec -T cassandra-1 cqlsh -e "CONSISTENCY QUORUM; SELECT order_id, status FROM mobilnyi_mir.orders_by_id WHERE order_id = 'ord_1003';"

echo "Token ring:"
docker-compose exec -T cassandra-1 nodetool ring | head -20
