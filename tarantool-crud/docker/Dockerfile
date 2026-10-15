ARG TARANTOOL_VERSION=2.11
FROM tarantool/tarantool:${TARANTOOL_VERSION}
WORKDIR /opt/tarantool
RUN if command -v apk >/dev/null; then apk add --no-cache git cmake make unzip; \
    else apt-get update && apt-get install -y --no-install-recommends git cmake make unzip && rm -rf /var/lib/apt/lists/*; fi
RUN if command -v tt >/dev/null; then rocks='tt rocks'; else rocks='tarantoolctl rocks'; fi \
    && $rocks install vshard 0.1.42 && $rocks install crud 1.8.0
