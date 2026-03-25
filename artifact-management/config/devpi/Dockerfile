# Dockerfile for custom devpi server image
#
# Use this if you need to customize devpi beyond the default image,
# e.g., adding plugins, custom configuration, or TLS certificates.
#
# Build:
#   docker build -t myorg/devpi-server:<tag> -f config/devpi/Dockerfile .
#
# Reference: https://devpi.net/docs/devpi/devpi/stable/

FROM python:3.12-alpine@sha256:<SHA256-Digest> 

RUN apk add --no-cache --virtual .build-deps gcc libc-dev && \
    pip install --no-cache-dir devpi-server devpi-web devpi-client && \
    apk del .build-deps

# Create non-root user
RUN useradd --create-home --home-dir /data --uid 1001 devpi

# Set correct file permissions
RUN chown -R devpi:devpi /data

# Switch to non-root user
USER devpi
WORKDIR /data

EXPOSE 3141

# Initialize the server data directory on first run
ENTRYPOINT ["devpi-server"]
CMD ["--host", "0.0.0.0", "--port", "3141", "--restrict-modify", "root", "--request-timeout", "60"]