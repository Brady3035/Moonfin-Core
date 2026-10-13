# Server fixtures for Silo support

Reference data that the `server_silo` and `playback_silo` code and tests are
written against. See `docs/silo/` for the plan these belong to.

## Pinned Silo contract

| | |
|---|---|
| File | `openapi-4b2e921c.json.gz` (gzipped `GET /api/v2/openapi.json`, OpenAPI 3.1) |
| Server build | `4b2e921c+dirty` (from `GET /api/v2/system/info` → `server_version`) |
| `api_major` | `2` |
| `contract_digest` | `12ea11dd8223e9426ab5376aad1116c150a674b432989b3cb4e5dbc9458b960a` |
| Captured | 2026-10-13 from the maintainer's test server |
| Size | 697 paths, 1,170 component schemas |

`contract_digest` is the SHA-256 of the uncompressed OpenAPI document (also
served as its `ETag`), so this check proves the file matches the server:

```sh
gunzip -c openapi-4b2e921c.json.gz | shasum -a 256
curl -s https://<silo-host>/api/v2/system/info   # compare contract_digest
```

`server_version` is a git short hash, not a semantic version (`+dirty` means
the server was built from a tree with local changes). Never parse it; Moonfin
checks `api_major` and logs the digest.

## Refreshing after a Silo upgrade

```sh
SILO_URL=https://<silo-host> scripts/silo_probe.sh --public --contract
```

This downloads the document, checks it against the server's `contract_digest`,
writes `openapi-<build>.json.gz` here with `gzip -9 -n` (so unchanged content
gives an identical file), removes the previous snapshot and prints the values
for the table above. Run it without `--public` (with `SILO_USERNAME`) to sample
the signed-in endpoints too; see `scripts/silo_probe.sh --help`.

## Samples

`silo/` (native `/api/v2` responses) and `emby/` (the same titles from Emby,
the shape the mappers must produce) are added in roadmap step 0.4. Signed query
parameters (`sig`, `st`, `exp`), tokens and server file paths are scrubbed.
