# Build context is the repository root. No cloud resources are created by this file.
FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/app/backend \
    SOURCE_CONFIG=/app/backend/sources.json \
    CONSUMER_BASELINE=/app/assets/policy/consumer_protection.json HOST=0.0.0.0 PORT=8080
WORKDIR /app
COPY backend/requirements*.txt /app/backend/
RUN pip install --no-cache-dir -r backend/requirements-cloud.txt && \
    groupadd --system wingman && useradd --system --gid wingman wingman
COPY backend/wingman_content /app/backend/wingman_content
COPY backend/sources.json /app/backend/sources.json
COPY assets/policy/consumer_protection.json /app/assets/policy/consumer_protection.json
USER wingman
EXPOSE 8080
ENTRYPOINT ["python", "-m", "wingman_content"]
CMD ["serve"]
