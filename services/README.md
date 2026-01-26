# Services

- **frontend**: React/TypeScript web interface
- **personaplex**: GPU-accelerated ML model runtime

## Build and Push

```bash
cp .env.example .env
./build-and-push.sh
```

Builds all services for linux/amd64 and pushes to ECR with timestamp tags.
