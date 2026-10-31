import "@typespec/http";
import "@typespec/openapi";
import "@typespec/openapi3";

using TypeSpec.Http;

@service(#{ title: "Matrix Four-Peer Demo API" })
@TypeSpec.OpenAPI.info(#{ version: "1.0.0" })
@server("http://10.77.0.1:8443", "Illustrative tinc address; replace per peer")
namespace Matrix;

/** See RFC 001 for strict parsing, signing, cross-field rules, and fault assumptions. */
@pattern("^[0-9a-f]{64}$")
scalar HashHex extends string;

@pattern("^[0-9a-f]{128}$")
scalar SignatureHex extends string;

@pattern("^[0-9a-f]{32}$")
scalar NonceHex extends string;

enum PeerId {
  a: "node_a",
  b: "node_b",
  c: "node_c",
  d: "node_d",
}

/** Trusted deployment input, distributed out of band; never learned from a request. */
model PeerConfiguration {
  id: PeerId;
  public_key_hex: HashHex;
  vpn_ip: string;
  api_url: string;
}

@pattern("^sha256:[0-9a-f]{64}$")
scalar DockerImageId extends string;

model TemplateConfiguration {
  template_id: "monte-carlo-v1";
  image_id: DockerImageId;
  algorithm_id: "xorshift32-u16-quartercircle-v1";
  cpu_limit: 1;
  memory_mib: 256;
  pids_limit: 64;
  timeout_seconds: 120;
  output_schema_version: 1;
}

/** config_hash is SHA256 of canonical JSON for exactly this object. */
model NetworkConfiguration {
  protocol_version: 1;
  @pattern("^[a-z0-9_-]{1,64}$")
  network_id: string;
  @minItems(4)
  @maxItems(4)
  peers: PeerConfiguration[];
  catalogue: TemplateConfiguration;
}

enum LocalExecutionState {
  none: "none",
  queued: "queued",
  running: "running",
  succeeded: "succeeded_local",
  aborted: "aborted_local",
  error: "error_local",
}

model MonteCarloParameters {
  @minValue(100000)
  @maxValue(10000000)
  samples: uint32;
  seed: uint32;
}

/** Hash exactly this model's canonical JSON; no defaults or additional properties. */
model JobSpec {
  protocol_version: 1;
  config_hash: HashHex;
  requester_id: PeerId;
  nonce: NonceHex;
  template_id: "monte-carlo-v1";
  parameters: MonteCarloParameters;
}

model JobRequest {
  domain: "matrix.job.v1";
  job_id: HashHex;
  spec: JobSpec;
}

/** Signature uses the pinned key of payload.spec.requester_id. */
model SignedJob {
  payload: JobRequest;
  signature: SignatureHex;
}

/** Exact integer result; samples and seed must equal the job parameters. */
model MonteCarloResult {
  schema_version: 1;
  @minValue(100000)
  @maxValue(10000000)
  samples: uint32;
  seed: uint32;
  /** Must be <= samples. Only independent execution may justify signing it. */
  @maxValue(10000000)
  hits: uint32;
}

model ExecutionAttestation {
  domain: "matrix.execution.v1";
  config_hash: HashHex;
  job_id: HashHex;
  result_hash: HashHex;
  signer_id: PeerId;
}

model SignedAttestation {
  payload: ExecutionAttestation;
  signature: SignatureHex;
}

/** A candidate is not a certificate. Sender may relay an existing attestation. */
model ResultAnnouncement {
  result: MonteCarloResult;
  attestation: SignedAttestation;
}

model ResultCertificate {
  protocol_version: 1;
  config_hash: HashHex;
  job_id: HashHex;
  result_hash: HashHex;
  /** Exactly two distinct matching signers, in lexicographic signer order. */
  @minItems(2)
  @maxItems(2)
  attestations: SignedAttestation[];
}

/** Self-contained evidence; hashes, signatures, and configuration must all match. */
model CertifiedResult {
  signed_job: SignedJob;
  result: MonteCarloResult;
  certificate: ResultCertificate;
}

model JobStorageReceipt {
  domain: "matrix.store-job.v1";
  config_hash: HashHex;
  job_id: HashHex;
  signer_id: PeerId;
  /** Signed retention deadline in Unix seconds; applies to this record's storage. */
  retained_until_unix: uint32;
}

model SignedJobReceipt {
  payload: JobStorageReceipt;
  signature: SignatureHex;
}

model ResultStorageReceipt {
  domain: "matrix.store-result.v1";
  config_hash: HashHex;
  job_id: HashHex;
  result_hash: HashHex;
  signer_id: PeerId;
  /** Holder persists signed job, result, and certificate through this deadline. */
  retained_until_unix: uint32;
}

model SignedResultReceipt {
  payload: ResultStorageReceipt;
  signature: SignatureHex;
}

/** Diagnostic values are hints, never execution votes or proof of finality. */
model Health {
  protocol_version: 1;
  peer_id: PeerId;
  config_hash: HashHex;
  paused: boolean;
  @minValue(0)
  @maxValue(1)
  running: uint32;
  @maxValue(8)
  queued: uint32;
}

model JobIndexEntry {
  job_id: HashHex;
  certified_hint: boolean;
}

model JobIndex {
  @maxItems(32)
  jobs: JobIndexEntry[];
}

model ExecutionAccepted {
  job_id: HashHex;
  /** Existing ID is returned on a duplicate active/successful request. */
  execution_id: NonceHex;
  local_state: LocalExecutionState;
}

model Ingested {
  stored: true;
  certified_hint: boolean;
}

model JobSnapshot {
  signed_job: SignedJob;
  local_state: LocalExecutionState;
  /** At most two distinct results per each of four signers. */
  @maxItems(8)
  announcements: ResultAnnouncement[];
  certified_result?: CertifiedResult;
  @maxItems(4)
  job_receipts: SignedJobReceipt[];
  @maxItems(4)
  result_receipts: SignedResultReceipt[];
}

enum ErrorCode {
  INVALID_SCHEMA,
  BAD_HASH,
  BAD_SIGNATURE,
  INVALID_CERTIFICATE,
  UNKNOWN_MEMBER,
  CONFIG_MISMATCH,
  UNKNOWN_JOB,
  JOB_CONFLICT,
  INVARIANT_VIOLATION,
  PAYLOAD_TOO_LARGE,
  PAUSED,
  QUEUE_FULL,
  JOB_LIMIT,
  IMAGE_UNAVAILABLE,
  LOCAL_STORAGE_ERROR,
}

model ErrorBody {
  code: ErrorCode;
  @maxLength(256)
  message: string;
  retryable: boolean;
}

@error
model ApiError {
  @statusCode status: 400 | 403 | 404 | 409 | 413 | 429 | 503;
  @body body: ErrorBody;
}

@route("/v1")
interface PeerApi {
  @get
  @route("/health")
  health(): Health;

  @get
  @route("/jobs")
  listJobs(): JobIndex;

  /** Persist the signed job before returning a signed storage receipt. */
  @put
  @route("/jobs/{job_id}")
  storeJob(@path job_id: HashHex, @body job: SignedJob): SignedJobReceipt | ApiError;

  @get
  @route("/jobs/{job_id}")
  getJob(@path job_id: HashHex): JobSnapshot | ApiError;

  /** Bodyless, idempotent request; requires an existing validated signed job. */
  @post
  @route("/jobs/{job_id}/execute")
  execute(@path job_id: HashHex): {
    @statusCode status: 202;
    @body body: ExecutionAccepted;
  } | ApiError;

  /** Verify and merge a signed candidate. Never trust certified_hint from a peer. */
  @post
  @route("/jobs/{job_id}/results")
  announceResult(@path job_id: HashHex, @body announcement: ResultAnnouncement): Ingested | ApiError;

  /** Persist the entire validated package before acknowledging result storage. */
  @post
  @route("/jobs/{job_id}/certificates")
  storeCertificate(@path job_id: HashHex, @body package: CertifiedResult): SignedResultReceipt | ApiError;
}
