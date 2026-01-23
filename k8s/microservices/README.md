# Microservices Helm Chart

Deploys microservices with automatic Deployment, Service, and Ingress (ALB) configuration.

## Features

- Automatic Deployment creation with health checks
- Automatic Service creation
- Optional Ingress with AWS ALB Controller integration
- External DNS integration
- Sensible defaults (enabled by default, minimal config required)

## Usage

### Minimal Configuration

```yaml
global:
  awsAccountId: "123456789012"
  awsRegion: us-east-1
  environment: dev

services:
  frontend:
    namespace:
      name: default
      create: true
    image:
      repository: frontend
      tag: latest
    ingress:
      enabled: true
      hostname: app.example.com
```

The image will be constructed as: `{awsAccountId}.dkr.ecr.{awsRegion}.amazonaws.com/{environment}/{repository}:{tag}`

### Full Configuration

```yaml
global:
  awsAccountId: "123456789012"
  awsRegion: us-east-1
  environment: dev

services:
  frontend:
    enabled: true
    namespace:
      name: default
      create: true
    image:
      repository: frontend
      tag: v1.0.0
    replicas: 2
    containerPort: 80
    servicePort: 80
    serviceType: ClusterIP
    imagePullPolicy: Always
    
    env:
      NODE_ENV: production
      API_URL: https://api.example.com
    
    healthCheck:
      path: /health
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
    
    ingress:
      enabled: true
      hostname: app.example.com
      scheme: internet-facing
      targetType: ip
      backendProtocol: HTTP
      ipAddressType: ipv4
      path: /
      pathType: Prefix
      healthCheckPath: /health
      certificateArn: arn:aws:acm:region:account:certificate/xxx
      targetGroupAttributes: stickiness.enabled=false
```

## Image Construction

Images are automatically constructed from global values:
```
{global.awsAccountId}.dkr.ecr.{global.awsRegion}.amazonaws.com/{global.environment}/{image.repository}:{image.tag}
```

Example: `123456789012.dkr.ecr.us-east-1.amazonaws.com/dev/frontend:latest`

## Defaults

- `namespace.create`: true
- `namespace.name`: default
- `enabled`: true
- `replicas`: 2
- `containerPort`: 80
- `servicePort`: 80
- `serviceType`: ClusterIP
- `imagePullPolicy`: Always
- `ingress.enabled`: false
- `ingress.scheme`: internet-facing
- `ingress.targetType`: ip
- `ingress.backendProtocol`: HTTP
- `ingress.path`: /
- `ingress.pathType`: Prefix
- Default resource limits applied if not specified

## Disable a Service

```yaml
services:
  frontend:
    enabled: false
```

## Disable Ingress

```yaml
services:
  backend:
    namespace:
      name: default
      create: false
    image:
      repository: backend
      tag: latest
    ingress:
      enabled: false
```

## Use Existing Namespace

```yaml
services:
  backend:
    namespace:
      name: my-existing-namespace
      create: false
```
