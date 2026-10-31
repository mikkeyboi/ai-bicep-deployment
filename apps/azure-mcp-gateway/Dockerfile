# Azure MCP gateway (feature 016). Built in ACR by scripts/deploy-azure-mcp.sh.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --require-hashes -r requirements.txt

COPY app.py foundry_tools.py image_tools.py ./
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin gateway
USER 10001

EXPOSE 8000
CMD ["python", "app.py"]
