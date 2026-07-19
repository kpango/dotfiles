---
name: ann-benchmark-patterns
description: ann-benchmarks フレームワーク規約(algos.yaml/HDF5/Pareto frontier分析)と ANN ベクトル検索の SIMD 距離カーネル最適化における落とし穴パターン(AVX2/AVX-512 ディスパッチャ検証・量子化の数学的等価性確認・部分集合とフルスケールの混同防止)。ArcFlare/NGT/NGTAQ 等の ANN R&D 作業時の参照用。実装作業自体は ann-perf-engineer agent に委譲する。
trigger: /ann-benchmark-patterns
---

# ANN Benchmark Patterns

## Core Principles

- A benchmark number is only as trustworthy as the verification behind it — dispatcher path, mathematical equivalence, and noise floor must all be checked before a recall/QPS delta is treated as a real effect.
- Recall should be stable run-to-run (±0.0001); QPS varies more (±5-15%) from system load. A recall swing is a bug signal, not noise.
- Subset-scale results (e.g. 30k/200k rows) are hypotheses, not conclusions — graph navigability and footprint constants that are slack at small N can become binding at full scale (e.g. 1M rows). Re-verify at target scale before claiming a win.
- Only same-machine relative comparisons are honest. Published baselines (often measured on different ISA, e.g. AVX-512) cannot be compared directly to local dev numbers (e.g. AVX2-only) — clone and run the baseline locally for a fair comparison.

## ann-benchmarks Framework Layout

```
ann_benchmarks/algorithms/<name>/
├── module.py     # BaseANN subclass: fit(X) / query(q, k) at minimum
├── Dockerfile    # build environment for this algorithm
└── config.yml    # algorithm registration
```

Benchmark configuration lives in `algos.yaml`: one block per index-build configuration (e.g. `alpha`, `max_edges`/`M`, `k_clusters`/`K`, quantization mode), with a swept list of query parameter sets (e.g. `[n_probe, ef, n_cluster_seeds, ...]`) spanning low-recall/high-throughput to high-recall/low-throughput. Comment each measured row with the date it was measured — these files accumulate historical Pareto data across sessions; never silently overwrite a measured row without a reason.

Datasets are HDF5 with `train`/`test`/`neighbors`/`distances` and an optional `metric` attribute.

## Metric Attribute Parsing (known gotcha)

`DATA.get('metric', ...)` or direct indexing can return the raw HDF5 dataset/attribute *object*, not a plain value. Indexing that object again with `[()]` raises `TypeError: byte indices must be integers or slices, not tuple`.

```python
# Wrong — assumes DATA.get() already unwrapped the value
metric = DATA.get('metric', b'euclidean')
if hasattr(metric, '__iter__') and not isinstance(metric, str):
    metric = bytes(metric[()]).decode()   # TypeError if metric is already a plain value

# Correct — check for dataset-ness before indexing, decode explicitly
if 'metric' in DATA:
    m = DATA['metric']
    if hasattr(m, 'shape'):                              # HDF5 dataset/attribute object
        metric = m[()].decode() if isinstance(m[()], bytes) else str(m[()])
    else:                                                  # already a plain value
        metric = m.decode() if isinstance(m, bytes) else str(m)
else:
    metric = 'euclidean'                                  # explicit fallback
```

## Pareto Frontier Dominance Check

Before adding a new `(recall, qps)` point to a configuration, verify it isn't dominated:

```python
def is_pareto(candidate, existing_points):
    r, q = candidate
    return not any(er >= r and eq >= q and (er > r or eq > q) for er, eq in existing_points)
```

Only integrate non-dominated points. Decision rule for "should we integrate gap-fill candidates before launching the next measurement phase": integrate only if **at least 3 candidates are non-dominated AND each fills a significant gap (≥0.002 recall increment)** — otherwise proceed with the existing frontier and skip integration.

## SIMD Dispatcher Verification

A dispatcher that's supposed to route to a SIMD path but silently falls back to scalar produces a benchmark result indistinguishable from "the optimization doesn't work" — when in fact it was never exercised. Always confirm the guard compiles as intended before interpreting a benchmark:

```cpp
inline float tier1_adc_fast_d(const int8_t* q, const uint8_t* data, int32_t q_sum, int D) {
    if (D == 128) return tier1_adc_fast(q, data, q_sum);   // hardwired fast path
#if defined(__AVX2__)                                       // <- MUST be present and taken
    return tier1_adc_avx2_d(q, data, q_sum, D);
#else
    return tier1_adc_scalar(q, data, q_sum, D);              // silent fallback if guard missing/false
#endif
}
```

Checklist before trusting a "no improvement" or "regression" result:
1. Confirm the build actually compiled with the target instruction set enabled (`-mavx2`/`-march=native` or equivalent, and the relevant `#if defined(__AVX2__)` etc. guards present).
2. Disassemble or grep the compiled binary for the expected instruction mnemonics if in doubt.
3. Re-run with a debug print of which dispatch branch was taken.

## Correctness-Before-Speed Gate

Any new SIMD kernel must pass a bit-identical (or documented-tolerance) check against a scalar reference **before** its benchmark numbers are trusted:

```cpp
int32_t result_simd   = dot_q_sq2(q_int8, sq2_code, D);
int32_t result_scalar = dot_q_sq2_scalar(q_int8, sq2_code, D);
assert(result_simd == result_scalar);  // integer kernels: exact match expected
```

A faster-but-wrong kernel yields a real speedup number with meaningless recall — always gate on correctness first.

## Quantization Scheme Selection

| Scheme | Footprint | Best fit | Caveat |
|---|---|---|---|
| SQ8 | 1 byte/dim | bandwidth-bound refinement stage | verify per-metric (L2 vs Angular) separately — a fix validated for one metric may not transfer |
| SQ4/SQ2 | 0.5/0.25 byte/dim | aggressive bandwidth reduction | precision loss compounds; always recall-match against baseline before accepting |
| RaBitQ 1-bit | `D/8` bytes/neighbor | **low-dimensional** data (e.g. D≈128) | footprint is dimension-dependent, not universal — can be *larger* than PQ baselines at high D (e.g. D≈960-1024) unless paired with a dimensionality-reduction front-end |
| RaBitQ 2-bit | `D/4` bytes/neighbor | high-dimensional data where 1-bit underperforms | still verify against both a low-dim and a high-dim dataset before claiming a general win |

Dimensionality-reduction front-end for RaBitQ at high D: use an **orthogonal** sub-projection (e.g. truncated SRHT/PCA), never a whitened one — whitening breaks the L2-distance-preserving identity RaBitQ's distance formula relies on.

## Common Mistakes to Catch

- Treating a subset-scale (30k/200k row) benchmark verdict as valid at full scale (1M+) without re-measuring — graph degree/navigability limits that are slack small can become the binding constraint at scale.
- Comparing your local AVX2 build's absolute QPS against a vendor's published AVX-512 numbers as if they were the same hardware.
- Accepting a "faster" SIMD kernel result without a scalar-reference correctness check.
- Reusing a cached index built under different quantization/metric parameters for a "fair" comparison.
- Padding `algos.yaml` with dominated (recall, QPS) points instead of only non-dominated ones.
- Running a project's blanket build-everything target when a narrow named target exists and other build artifacts are known to be sensitive to full rebuilds.
