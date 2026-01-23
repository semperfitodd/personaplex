# Services

Microservices for Personaplex.

## Build and Push to ECR

```bash
cp .env.example .env
# Edit .env with your values

chmod +x build-and-push.sh
./build-and-push.sh
```

The script will:
- Build all services with Dockerfiles for linux/amd64
- Tag with timestamp (YYYYMMDDHHMMSS)
- Push to ECR at `{account}.dkr.ecr.{region}.amazonaws.com/{environment}/{service}`
