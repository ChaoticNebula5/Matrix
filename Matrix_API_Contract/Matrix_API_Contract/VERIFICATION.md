# Specification verification

Prepared 31 October 2026. These checks concern the deliverable, not an implemented distributed service.

- TypeSpec compiler 1.17.0 compiled `main.tsp` and emitted OpenAPI without compiler errors or warnings.
- Generated OpenAPI is version 3.0.0, describes API version 1.0.0, and includes all seven operations from RFC 001.
- The emitted execution-certificate schema requires exactly two attestations; distinctness, matching bindings, ordering, and signatures remain runtime checks.
- Canonical JSON strings and SHA-256 hashes in `protocol_vectors.json` were recomputed and matched.
- Ed25519 job and execution signatures in the public test vectors verified; changing a signed sample count caused signature rejection.
- The sample certificate has two distinct, sorted signers with matching job, result, and configuration hashes.
- Sample signed job, result, and certificate-package sizes fit the RFC body limits.
- The two workload fixtures were calculated from the RFC integer reference algorithm.
- RFC sections and code fences were checked for completeness/balance.

Not performed: implementation of the Python agent, FastAPI conformance tests, Docker execution, tinc installation, physical-machine determinism tests, fault injection, partitions, recovery, performance measurements, or a production security review. Those remain the implementation acceptance gates in the RFC.
