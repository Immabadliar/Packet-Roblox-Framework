# Packet Benchmarks

These scripts are intentionally outside the Rojo project tree. Run them in a Roblox Studio test place after syncing the Packet folder into `ReplicatedStorage`.

## Microbenchmarks

Run `Microbench.luau` from the command bar or a temporary server script. It measures:

- schema validation
- encoding
- decoding
- encode plus decode
- `Packet.Get`
- `Packet.Exists`

Record the output before changing runtime code. Run it several times and use the median rather than a single run.

## End-to-end stress test

Run `Stress.server.luau` in `ServerScriptService` and `Stress.client.luau` in `StarterPlayerScripts`.

The client runs a zero-packet baseline followed by 1, 5, 10, 25, 50, and 100 packets per rendered frame. Each level runs for 10 seconds.

The scripts report:

- attempted packets
- received packets
- dropped packets
- packets per second
- client FPS
- average, p95, p99, and worst client frame time
- average, p95, p99, and worst server Heartbeat time

Run the test with `DEBUG_DISABLE_RATE_LIMITER = false`. Repeat with it set to `true` only as a diagnostic comparison; do not use that setting as a security or production baseline.

For meaningful comparisons, keep the Studio place, client quality level, test player count, packet schema, and benchmark duration unchanged. Capture Studio MicroProfiler and Lua heap/GC data for allocation comparisons.

The current repository has no Roblox runtime available, so these measurements must be collected in Studio before an optimization is accepted.
