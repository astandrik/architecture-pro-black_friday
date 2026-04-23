#!/bin/bash

cd "$(dirname "$0")/.."

echo "Total:"
docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Shard 1:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Shard 2:"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
