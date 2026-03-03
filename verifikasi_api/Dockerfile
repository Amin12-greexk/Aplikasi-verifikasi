FROM dart:stable AS build
WORKDIR /app

COPY pubspec.yaml pubspec.yaml
COPY analysis_options.yaml analysis_options.yaml
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates libsqlite3-0 \
  && ln -s /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib/x86_64-linux-gnu/libsqlite3.so \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/server /app/server

ENV PORT=8080
ENV DB_PATH=/data/log.db

VOLUME ["/data"]
EXPOSE 8080

CMD ["/app/server"]
