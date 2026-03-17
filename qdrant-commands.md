## Collection was lost after the last redeploy. Recreate it quickly:
# bash# 1. Create fresh collection with 300 points

python3 tests/load-test.py \
  --base-url http://127.0.0.1:6333 \
  --collection tkxel_collection \
  --points 300 \
  --batch-size 50 \
  --search-rounds 25 \
  --shard-number 3 \
  --replication-factor 2

# 2. Verify all shards Active and 300 points
curl -s http://127.0.0.1:6333/collections/tkxel_collection/cluster | python3 -m json.tool
curl -s http://127.0.0.1:6333/collections/tkxel_collection | python3 -m json.tool | grep points_count



## Insert Data 
curl -X PUT http://localhost:6333/collections/test_vectors \
-H "Content-Type: application/json" \
-d '{
  "vectors": {
    "size": 4,
    "distance": "Cosine"
  },
  "shard_number": 3,
  "replication_factor": 2
}'

---

## Then check cluster status:
curl http://localhost:6333/cluster


## Visualize Shard Distribution
which node stores which shard:

curl http://localhost:6333/collections


# Inspect Collection:
curl http://localhost:6333/collections/my_vectors/cluster

# Kubernetes Service:
                          │
                          ▼
              ┌───────────┼───────────┐
              │           │           │
           qdrant-0    qdrant-1    qdrant-2
            Leader      Follower     Follower
              │           │           │
         shard-1       shard-2       shard-3
           replica       replica       replica

---

## Test Vector Search Across Nodes

# Insert some data
curl -X PUT http://localhost:6333/collections/test_vectors \
-H "Content-Type: application/json" \
-d '{
  "vectors": {
    "size": 4,
    "distance": "Cosine"
  },
  "shard_number": 3,
  "replication_factor": 2
}'


## Delete collection
curl -X DELETE http://127.0.0.1:6333/collections/ha_validation_collection

## Confirm Deletion
curl -s http://127.0.0.1:6333/collections | python3 -m json.tool

## AFTER RESTORE
# Check collection exists
curl -s http://127.0.0.1:6333/collections | python3 -m json.tool

# Check point count
curl -s http://127.0.0.1:6333/collections/ha_validation_collection | python3 -m json.tool | grep points_count