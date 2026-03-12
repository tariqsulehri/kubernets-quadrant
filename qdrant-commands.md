
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

