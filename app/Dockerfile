FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY linkforge ./linkforge

EXPOSE 8080

# One Uvicorn process per task keeps ECS CPU metrics meaningful for autoscaling.
CMD ["uvicorn", "linkforge.main:app", "--host", "0.0.0.0", "--port", "8080"]
