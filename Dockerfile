FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gnucobol \
    python3 \
    make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

RUN make data && make build

CMD ["./bin/CLRENGIN"]
