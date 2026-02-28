#!/bin/bash
set -e

cd "$(dirname "$0")/.."

docker-compose exec -T cassandra-1 cqlsh <<'EOF'

CREATE KEYSPACE IF NOT EXISTS mobilnyi_mir
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3
};

USE mobilnyi_mir;

CREATE TYPE IF NOT EXISTS cart_item (
  product_id TEXT,
  quantity INT
);

CREATE TABLE IF NOT EXISTS carts_by_user (
  user_id TEXT,
  status TEXT,
  updated_at TIMESTAMP,
  cart_id UUID,
  items LIST<FROZEN<cart_item>>,
  created_at TIMESTAMP,
  PRIMARY KEY ((user_id), status, updated_at)
) WITH CLUSTERING ORDER BY (status ASC, updated_at DESC)
  AND default_time_to_live = 86400;

CREATE TABLE IF NOT EXISTS carts_by_session (
  session_id TEXT,
  cart_id UUID,
  items LIST<FROZEN<cart_item>>,
  status TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  PRIMARY KEY ((session_id))
) WITH default_time_to_live = 86400;

CREATE TABLE IF NOT EXISTS user_sessions (
  session_id TEXT,
  user_id TEXT,
  created_at TIMESTAMP,
  last_activity TIMESTAMP,
  ip_address TEXT,
  user_agent TEXT,
  PRIMARY KEY ((session_id))
) WITH default_time_to_live = 3600;

EOF

docker-compose exec -T cassandra-1 cqlsh -e "USE mobilnyi_mir; DESCRIBE TABLES;"
