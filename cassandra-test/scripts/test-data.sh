#!/bin/bash
set -e

cd "$(dirname "$0")/.."

docker-compose exec -T cassandra-1 nodetool status

docker-compose exec -T cassandra-1 cqlsh <<'EOF'
USE mobilnyi_mir;

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

echo "QUORUM read (carts):"
docker-compose exec -T cassandra-1 cqlsh -e "CONSISTENCY QUORUM; SELECT user_id, status, cart_id FROM mobilnyi_mir.carts_by_user WHERE user_id = 'cust_001' AND status = 'active';"

echo "Token ring:"
docker-compose exec -T cassandra-1 nodetool ring | head -20
