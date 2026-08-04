# ---------- Stage 1 : Builder ----------
FROM python:3.13-slim AS builder

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir \
    --prefix=/install \
    -r requirements.txt


# ---------- Stage 2 : Runtime ----------
FROM python:3.13-slim

WORKDIR /app

COPY --from=builder /install /usr/local

COPY app.py .
COPY config.py .
COPY templates ./templates

EXPOSE 5000

CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--access-logfile", "-", \
     "--access-logformat", "%(m)s %(U)s %(s)s %(D)sµs", \
     "--error-logfile", "-", \
     "app:app"]
