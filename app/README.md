# LinkForge application

This is the intentionally temporary application for `v2-fargate`. It exposes
the ALB health endpoint and redirects two fixed codes from an in-memory map.
`v4-state` replaces the map with DynamoDB; no persistent-link API belongs here
before then.

The container listens on port `8080`, so the ECS task definition, security
group, and target group should all use that port.

## Run locally

```sh
python -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
pytest
uvicorn linkforge.main:app --host 0.0.0.0 --port 8080
```

`GET /health` returns `{"status":"ok"}`. `GET /docs` and `GET /repo` return
302 redirects. Any other code returns 404.

## Build the image

Run this from the repository root:

```sh
docker build --tag linkforge:v2 ./app
docker run --rm --publish 8080:8080 linkforge:v2
```

The image starts exactly one Uvicorn process. ECS controls replica count and
uses CPU as an autoscaling signal, so application workers must not be added to
the container command.
