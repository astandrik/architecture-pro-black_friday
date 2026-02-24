#!/bin/bash

cd "$(dirname "$0")/.."

docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({_id: "config_rs", configsvr: true, members: [{_id: 0, host: "configSrv:27019"}]})
EOF
sleep 3

docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard1_rs", members: [{_id: 0, host: "shard1:27018"}]})
EOF
sleep 3

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard2_rs", members: [{_id: 0, host: "shard2:27018"}]})
EOF
sleep 3

echo "Waiting for mongos_router to be ready..."
until docker compose exec -T mongos_router mongosh --port 27017 --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  sleep 2
  echo "  mongos_router not ready yet, retrying..."
done
echo "mongos_router is ready."

docker compose exec -T mongos_router mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1_rs/shard1:27018")
sh.addShard("shard2_rs/shard2:27018")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", {"_id": "hashed"})
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly" + i})
db.helloDoc.countDocuments()
EOF
