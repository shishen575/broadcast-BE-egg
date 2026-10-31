FROM debian:bookworm-slim

# BDS needs libcurl/openssl, MCXboxBroadcast needs a JRE, the rest is tooling.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl jq unzip tzdata iproute2 libcurl4 libssl3 openjdk-17-jre-headless \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -d /home/container -s /bin/bash container

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 start.sh /opt/start.sh

CMD ["/bin/bash", "/entrypoint.sh"]
