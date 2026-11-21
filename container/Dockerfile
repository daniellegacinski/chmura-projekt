# Obraz z modułem reguł (Lab 7). Budować z głównego folderu repo:
#   docker build -f container/Dockerfile -t zlecenia-rules .
FROM python:3.12-slim

ARG APP_VERSION=dev
ARG GIT_SHA=local
ENV APP_VERSION=$APP_VERSION \
    GIT_SHA=$GIT_SHA \
    PYTHONUNBUFFERED=1

WORKDIR /app
# Ten sam moduł reguł, który testujemy i który działa w funkcji przetwarzającej
COPY src/processor/rules.py container/app.py ./

USER nobody
EXPOSE 8080
CMD ["python", "app.py"]