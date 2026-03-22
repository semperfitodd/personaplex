# PersonaPlex

EKS-hosted, GPU-accelerated real-time speech-to-speech AI assistant powered by the NVIDIA PersonaPlex-7B model. Users connect via browser WebSocket and have a spoken conversation with the AI. Custom voice personas can be generated from uploaded WAV files and stored in S3.

## Architecture

```
Browser (WebSocket)
  └─ ALB (HTTPS) → frontend nginx pod
       ├─ GET /api/voices → personaplex pod :8999 (voices REST)
       └─ WS  /api/       → personaplex pod :8998 (Moshi WSS, self-signed cert)
```

**Key design decisions:**
- The `personaplex` pod is cluster-internal only — no public ingress. The frontend nginx reverse-proxies WebSocket connections with `proxy_ssl_verify off` for the self-signed Moshi cert.
- S3 voice files are mounted directly into pods via Mountpoint S3 CSI as PersistentVolumes. No container rebuilds are needed when adding new voices.
- GPU nodes are tainted `nvidia.com/gpu=true:NoSchedule`. Only the `personaplex` deployment tolerates this taint.
- Image deploys are GitOps-driven: `build-and-push.py` patches `k8s/microservices/values.yaml` with the new timestamp tag; ArgoCD self-heals on the git change.

## Repository Layout

```
personaplex/
├── terraform/              # AWS infrastructure (flat single-root module)
├── k8s/
│   ├── master/             # App-of-Apps bootstrap (ArgoCD AppProjects + Applications)
│   ├── devops/             # Platform tooling (ArgoCD, ALB controller, ExternalDNS, NVIDIA plugin)
│   └── microservices/      # Application workloads (frontend, personaplex, voice-generator)
├── services/
│   ├── frontend/           # Vite + nginx UI
│   ├── personaplex/        # NVIDIA Moshi inference server
│   └── voice-generator/    # One-shot voice embedding job
└── argocd_initial_start/   # Bootstrap config for initial ArgoCD install
```

## Infrastructure (Terraform)

All Terraform lives in `terraform/` as a flat single-root module. State is stored in S3, configured via `backend.hcl` (gitignored — copy from `backend.hcl.example`).

| Resource | Details |
|---|---|
| VPC | `10.0.0.0/16`, 3 AZs, public + private subnets, single NAT, VPC Flow Logs |
| VPC Endpoints | S3 (Gateway), ECR API + ECR DKR (Interface) |
| EKS | Kubernetes 1.35, `personaplex` cluster |
| CPU nodes | `t3.large` SPOT, min 1 / max 5 / desired 2, AL2023 x86_64 |
| GPU nodes | `g6.2xlarge` ON_DEMAND, min 0 / max 3 / desired 1, AL2023 NVIDIA AMI, tainted `nvidia.com/gpu=true:NoSchedule` |
| Node volumes | 100 GB gp3, encrypted, 3000 IOPS |
| EKS Addons | `aws-ebs-csi-driver`, `aws-mountpoint-s3-csi-driver`, `aws-secrets-store-csi-driver-provider`, `coredns`, `kube-proxy`, `metrics-server`, `vpc-cni` |
| S3 | `personaplex-ptfiles-<suffix>` (voice WAV files), `personaplex-wavfiles-<suffix>` (input WAV samples) |
| Secrets Manager | `personaplex/hf-token` — populate `HF_TOKEN` manually after `terraform apply` |
| ECR | `personaplex/frontend`, `personaplex/personaplex`, `personaplex/voice-generator` |
| ACM | Certificates for `personaplex.<domain>` and `personaplex-argocd.<domain>` |

**IRSA Roles:**

| Role | Service Account | Permissions |
|---|---|---|
| `personaplex-ebs-csi` | `kube-system:ebs-csi-controller-sa` | EBS CSI controller |
| `personaplex-s3-csi` | `kube-system:s3-csi-driver-sa` | S3 Mountpoint CSI (all buckets) |
| `personaplex-personaplex-secrets` | `personaplex:personaplex-sa` | `secretsmanager:GetSecretValue` on HF token |
| `personaplex-voice-generator-sa` | `personaplex:voice-generator-sa` | `s3:PutObject` on ptfiles bucket |

**Deploy:**

```bash
cd terraform
cp backend.hcl.example backend.hcl   # fill in your state bucket
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init -backend-config=backend.hcl
terraform apply
# After apply: populate the HF token in Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id personaplex/hf-token \
  --secret-string '{"HF_TOKEN":"hf_..."}'
```

## Kubernetes / GitOps (ArgoCD)

**App-of-Apps pattern:**

```
argocd_initial_start/config.yaml  ← one-time bootstrap helm install
  └─ k8s/master/                  ← creates AppProjects + Applications
       ├─ k8s/devops/              ← platform tooling
       └─ k8s/microservices/       ← application workloads
```

**Bootstrap (one-time):**

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd
helm install argo-cd argo/argo-cd --namespace argocd --values argocd_initial_start/config.yaml
helm template master/ -f master/values.dev.yaml | kubectl apply -f -
```

### `k8s/devops/` — Platform Tooling

| Chart | Version | Purpose |
|---|---|---|
| `argo-cd` | 9.4.15 | GitOps controller |
| `aws-load-balancer-controller` | 3.1.0 | ALB provisioning |
| `external-dns` | 1.20.0 | Route53 DNS automation |
| `nvidia-device-plugin` | 0.19.0 | GPU device discovery |

Also deploys: ArgoCD ALB Ingress, `ebs-sc` StorageClass (gp3, Retain), S3 CSI RBAC.

### `k8s/microservices/` — Application Workloads

Generic Helm templates render Deployments, Services, Ingresses, Jobs, ServiceAccounts, SecretProviderClasses, and S3 PVs/PVCs from `values.yaml`.

**Deployments:**

| Service | Namespace | Replicas | Port(s) | Ingress |
|---|---|---|---|---|
| `frontend` | `frontend` | 2 | 80 | `personaplex.<domain>` (internet-facing ALB, HTTPS) |
| `personaplex` | `personaplex` | 1 | 8998 (WSS), 8999 (REST) | None — cluster-internal |

**Jobs:**

| Job | Namespace | Trigger |
|---|---|---|
| `voice-generator` | `personaplex` | Manual (set `enabled: true`, git push) |

**S3 Volume Mounts:**

| Pod | Bucket | Mount | Access |
|---|---|---|---|
| `personaplex` | ptfiles | `/mnt/models` | ReadOnly |
| `voice-generator` | wavfiles | `/mnt/input` | ReadOnly |
| `voice-generator` | ptfiles | `/mnt/output` | ReadWrite |

## Services

### `services/frontend/`

Vite 6 single-page app served by nginx. Captures microphone audio, encodes to Opus, and streams over WebSocket to the Moshi server. Receives Opus-encoded AI speech back and plays it via a custom `AudioWorkletProcessor` with adaptive jitter buffering.

**Features:** Voice selector (fetches `/api/voices`, groups by category), system prompt presets, inference parameter controls (`text_temperature`, `text_topk`, `audio_temperature`, `audio_topk`, `repetition_penalty`, `pad_mult`), live transcript display, mic-reactive animated orb.

**WebSocket binary protocol:**

| Byte | Type |
|---|---|
| `0x00` | HANDSHAKE |
| `0x01` | AUDIO (Opus Ogg) |
| `0x02` | TEXT (transcript) |
| `0x03` | CONTROL |
| `0x04` | METADATA (JSON) |
| `0x05` | ERROR |
| `0x06` | PING |

**Nginx proxy routes:**
- `GET /api/voices` → `personaplex.personaplex.svc.cluster.local:8999`
- `WS /api/` → `personaplex.personaplex.svc.cluster.local:8998` (HTTPS, ssl verify off, 24hr timeouts)
- `/health` → 200 stub

### `services/personaplex/`

Python 3.11 server running on `nvidia/cuda:12.4.0-runtime-ubuntu22.04`. Manages two endpoints:

1. **Port 8999** — lightweight `HTTPServer` serving `GET /api/voices`. Lists available voices from the HuggingFace model snapshot directory, including custom WAV files symlinked from `/mnt/models`. A background thread polls every 30s to link new voices as they appear.

2. **Port 8998** — `python3 -m moshi.server` subprocess with a self-signed SSL certificate. Handles WebSocket speech-to-speech inference using the `nvidia/personaplex-7b-v1` model. Model weights are downloaded lazily from HuggingFace on first request using `HF_TOKEN` from Secrets Manager.

**Key environment variables:**

| Variable | Purpose |
|---|---|
| `HF_TOKEN` | HuggingFace auth for model download |
| `CPU_OFFLOAD` | Set `"true"` to offload model layers to CPU (default: `"false"`) |
| `MODELS_DIR` | S3 Mountpoint path for custom voice WAV files (default: `/mnt/models`) |
| `PYTORCH_CUDA_ALLOC_CONF` | `expandable_segments:True` — reduces CUDA OOM fragmentation |
| `TORCHDYNAMO_DISABLE` | Disables torch.compile for compatibility |
| `CUDA_MODULE_LOADING` | `LAZY` — faster container startup |
| `OMP_NUM_THREADS` | CPU thread limit for OpenMP |

**Health probes:** Startup probe hits port 8999 `/api/voices` (available within seconds of container start). Liveness probe hits port 8998 `/` via HTTPS so a hung Moshi subprocess triggers a pod restart.

### `services/voice-generator/`

Python 3.11 batch job on `python:3.11-slim`. CPU-only — no GPU required. Converts a set of WAV audio samples into a single voice prompt WAV that PersonaPlex loads as a custom voice.

**Pipeline (`generate_voice_prompt.py`):**
1. Read all `*.wav` from `/mnt/input/wavs` (S3 wavfiles bucket)
2. Resample each to 24 kHz mono
3. Concatenate with 300ms silence between clips
4. Write combined audio as `<stem>_<UTC_timestamp>.wav`
5. Upload to S3 ptfiles bucket

The output WAV is picked up by the `personaplex` pod's voice linker loop and symlinked into the Moshi model snapshot voices directory, making it immediately selectable in the UI.

**Key environment variables:**

| Variable | Purpose |
|---|---|
| `WAV_DIR` | Input WAV directory (default: `/mnt/input/wavs`) |
| `OUTPUT_PATH` | Output filename stem (default: `voice_prompt.wav`) |
| `S3_OUTPUT_BUCKET` | S3 bucket for upload |
| `AWS_REGION` | AWS region for S3 client (default: `us-east-1`) |

## Build & Deploy

```bash
cd services
cp .env.example .env       # fill in AWS_ACCOUNT_ID, AWS_REGION, ENVIRONMENT
python3 build-and-push.py              # build only changed services
python3 build-and-push.py --force      # rebuild all
python3 build-and-push.py frontend     # build one specific service
git add k8s/microservices/values.yaml
git commit -m "deploy: update image tags"
git push                               # ArgoCD auto-syncs
```

The build script SHA-256 hashes each service directory and skips unchanged services. After a successful push it patches the image tag in `k8s/microservices/values.yaml` automatically.

## Adding a Custom Voice

1. Upload WAV files to the S3 wavfiles bucket under a `wavs/` prefix:
   ```bash
   aws s3 cp my_voice.wav s3://personaplex-wavfiles-<suffix>/wavs/
   ```
2. Trigger the voice-generator job by setting `enabled: true` in `k8s/microservices/values.yaml` under `jobs.voice-generator`, committing, and pushing. ArgoCD will create the Job.
3. The resulting WAV is uploaded to the ptfiles bucket and the `personaplex` pod's background thread links it into the Moshi voices directory within 30 seconds. It appears in the UI voice selector under **Custom**.
4. Reset `enabled: true` → `enabled: false` (or leave as-is; completed Jobs are not re-run by Kubernetes).

## Environment URLs

| Service | URL |
|---|---|
| App | `https://personaplex.<domain>` |
| ArgoCD | `https://personaplex-argocd.<domain>` |
