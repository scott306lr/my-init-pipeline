# Clean-room test image: stock Ubuntu 22.04, a non-root user, no SSH key.
# Only what a bare server can be assumed to have, plus python3 (needed by the
# claude setup repo's install.sh). Build and run via tests/docker.sh.
FROM ubuntu:22.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl git python3 \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash tester
USER tester
WORKDIR /home/tester
ENV LANG=C.UTF-8

COPY --chown=tester:tester . /home/tester/my-init-pipeline
