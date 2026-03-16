#!/usr/bin/env python3

"""Basic Qdrant write and query load test for HA validation."""

from __future__ import annotations

import argparse
import json
import statistics
import time
import urllib.error
import urllib.request
from typing import Any


def request_json(base_url: str, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    body = None
    headers = {"Content-Type": "application/json"}

    if payload is not None:
      body = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(f"{base_url.rstrip('/')}{path}", data=body, headers=headers, method=method)

    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def deterministic_vector(point_id: int, size: int) -> list[float]:
    return [round(((point_id + index) % 17) / 17, 6) for index in range(size)]


def ensure_collection(base_url: str, collection: str, vector_size: int, shard_number: int, replication_factor: int) -> None:
    payload = {
        "vectors": {"size": vector_size, "distance": "Cosine"},
        "shard_number": shard_number,
        "replication_factor": replication_factor,
    }

    request_json(base_url, "PUT", f"/collections/{collection}", payload)


def upsert_points(base_url: str, collection: str, start_id: int, count: int, vector_size: int) -> None:
    points = []
    for point_id in range(start_id, start_id + count):
        points.append(
            {
                "id": point_id,
                "vector": deterministic_vector(point_id, vector_size),
                "payload": {
                    "batch": start_id,
                    "source": "ha-validation",
                },
            }
        )

    request_json(
        base_url,
        "PUT",
        f"/collections/{collection}/points?wait=true",
        {"points": points},
    )


def search_points(base_url: str, collection: str, vector_size: int, limit: int) -> int:
    payload = {
        "vector": deterministic_vector(1, vector_size),
        "limit": limit,
        "with_payload": False,
        "with_vector": False,
    }

    response = request_json(base_url, "POST", f"/collections/{collection}/points/search", payload)
    return len(response.get("result", []))


def collection_points_count(base_url: str, collection: str) -> int:
    response = request_json(base_url, "GET", f"/collections/{collection}")
    result = response.get("result", {})
    return int(result.get("points_count", 0))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a simple Qdrant HA load test")
    parser.add_argument("--base-url", default="http://127.0.0.1:6333", help="Qdrant base URL")
    parser.add_argument("--collection", default="ha_validation_collection", help="Collection name")
    parser.add_argument("--vector-size", type=int, default=4, help="Vector size to use")
    parser.add_argument("--points", type=int, default=300, help="Total points to upsert")
    parser.add_argument("--batch-size", type=int, default=50, help="Points per batch")
    parser.add_argument("--search-rounds", type=int, default=25, help="Number of search requests")
    parser.add_argument("--limit", type=int, default=5, help="Search result limit")
    parser.add_argument("--shard-number", type=int, default=3, help="Collection shard count")
    parser.add_argument("--replication-factor", type=int, default=2, help="Collection replication factor")
    parser.add_argument("--skip-create", action="store_true", help="Skip collection creation")
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    try:
        if not args.skip_create:
            ensure_collection(
                args.base_url,
                args.collection,
                args.vector_size,
                args.shard_number,
                args.replication_factor,
            )

        write_latencies: list[float] = []
        for start_id in range(0, args.points, args.batch_size):
            batch_count = min(args.batch_size, args.points - start_id)
            started_at = time.perf_counter()
            upsert_points(args.base_url, args.collection, start_id, batch_count, args.vector_size)
            write_latencies.append(time.perf_counter() - started_at)

        search_latencies: list[float] = []
        search_result_sizes: list[int] = []
        for _ in range(args.search_rounds):
            started_at = time.perf_counter()
            search_result_sizes.append(search_points(args.base_url, args.collection, args.vector_size, args.limit))
            search_latencies.append(time.perf_counter() - started_at)

        point_count = collection_points_count(args.base_url, args.collection)

        print("Load test completed successfully.")
        print(f"Collection: {args.collection}")
        print(f"Points reported by Qdrant: {point_count}")
        print(f"Write batches: {len(write_latencies)}")
        print(f"Average write latency: {statistics.mean(write_latencies):.4f}s")
        print(f"P95 write latency: {statistics.quantiles(write_latencies, n=20)[18]:.4f}s" if len(write_latencies) > 1 else f"P95 write latency: {write_latencies[0]:.4f}s")
        print(f"Search rounds: {len(search_latencies)}")
        print(f"Average search latency: {statistics.mean(search_latencies):.4f}s")
        print(f"P95 search latency: {statistics.quantiles(search_latencies, n=20)[18]:.4f}s" if len(search_latencies) > 1 else f"P95 search latency: {search_latencies[0]:.4f}s")
        print(f"Search result sizes: min={min(search_result_sizes)}, max={max(search_result_sizes)}")
    except urllib.error.HTTPError as error:
        print(f"HTTP error {error.code}: {error.read().decode('utf-8')}")
        raise SystemExit(1) from error
    except urllib.error.URLError as error:
        print(f"Connection error: {error}")
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
