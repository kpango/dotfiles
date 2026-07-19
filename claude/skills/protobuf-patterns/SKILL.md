---
name: protobuf-patterns
description: Protobuf schema design, breaking change avoidance, buf lint/breaking rules, gRPC service patterns, and code generation workflows for production APIs.
trigger: /protobuf-patterns
---

# Protobuf Patterns

## Core Principles

- Field numbers are permanent — never reuse a deleted field number
- Adding fields is safe; removing, renumbering, or changing types is breaking
- Use `buf` for linting, breaking change detection, and code generation
- In vald: edit `.proto` only, then run `make proto/all` — never edit `*.pb.go`

## File Layout

```proto
syntax = "proto3";

package vald.v1;

option go_package = "github.com/vdaas/vald/apis/grpc/v1/vald";
option java_multiple_files = true;
option java_package = "org.vdaas.vald.api.v1.vald";

import "google/api/annotations.proto";
import "buf/validate/validate.proto";
```

## Field Numbering

```proto
message SearchRequest {
  // 1-15: single byte encoding — use for hot-path fields
  repeated float vector = 1;
  string id = 2;

  // 16-2047: two byte encoding
  SearchConfig config = 16;

  // Never reuse: always reserve deleted numbers and names
  reserved 3, 4;
  reserved "deprecated_field";
}
```

## Safe vs Breaking Changes

```proto
// SAFE
message Request {
  string id = 1;
  string label = 3;           // new field, new number
  optional string hint = 4;   // proto3 optional for presence detection
}

// BREAKING — never do in production
// int32 id = 1;              ← type change from string
// string name = 1;           ← rename with same number (JSON breaking)
// removing field 2 without reserving
```

## Message Design

```proto
// Oneof for mutually exclusive fields
message Filter {
  oneof condition {
    string exact = 1;
    RangeFilter range = 2;
    RegexFilter regex = 3;
  }
}

// Well-known types
import "google/protobuf/timestamp.proto";
import "google/protobuf/duration.proto";
import "google/protobuf/empty.proto";
import "google/protobuf/wrappers.proto";

message Event {
  google.protobuf.Timestamp created_at = 1;
  google.protobuf.Duration ttl = 2;
  google.protobuf.Int32Value timeout_ms = 3;  // null = use default
}
```

## gRPC Service Patterns

```proto
service Search {
  // Unary
  rpc Search(SearchRequest) returns (SearchResponse) {
    option (google.api.http) = { post: "/v1/search"; body: "*" };
  };

  // Server streaming
  rpc StreamSearch(SearchRequest) returns (stream SearchResponse);

  // Bidirectional streaming
  rpc StreamMultiSearch(stream SearchRequest) returns (stream SearchResponse);
}
```

## Validation

```proto
import "buf/validate/validate.proto";

message InsertRequest {
  string id = 1 [(buf.validate.field).string = {
    min_len: 1,
    max_len: 256,
    pattern: "^[a-zA-Z0-9_-]+$"
  }];

  repeated float vector = 2 [(buf.validate.field).repeated = {
    min_items: 1,
    max_items: 65536
  }];
}
```

## buf.yaml

```yaml
version: v2
modules:
  - path: apis/proto
    name: buf.build/vdaas/vald
lint:
  use:
    - STANDARD
  except:
    - PACKAGE_VERSION_SUFFIX
breaking:
  use:
    - FILE
```

## buf Workflow

```bash
buf lint                                          # lint
buf breaking --against .git#branch=main          # check breaking changes
buf format -w                                     # format in-place
buf build                                         # validate descriptor

# In vald — never run buf generate directly:
make proto/all    # Go + Rust + Swagger generation
make proto/go     # Go only
```

## gRPC Error Handling (Go)

```go
import (
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
)

if id == "" {
    return nil, status.Error(codes.InvalidArgument, "id is required")
}
if !found {
    return nil, status.Errorf(codes.NotFound, "id %q not found", id)
}
```

## Anti-Patterns

- Never reuse field numbers, even years after reserving them
- Don't use `required` (proto2) — it breaks schema evolution
- Don't embed large blobs in messages — use a reference + separate store
- Don't use `sint32`/`sint64` unless values are frequently negative
- Never edit generated `*.pb.go` / `*_vtproto.pb.go` — always edit `.proto`
