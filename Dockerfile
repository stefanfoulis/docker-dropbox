# Based on Ubuntu 22.04
FROM ubuntu:22.04

# Maintainer
LABEL maintainer "Alexander Graf <alex@otherguy.io>"

# Required to prevent warnings
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NONINTERACTIVE_SEEN=true

# Change working directory
WORKDIR /opt/dropbox

# Not really required for --net=host
EXPOSE 17500

# Set language
ENV LANG   "C.UTF-8"
ENV LC_ALL "C.UTF-8"

# Install prerequisites
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
   software-properties-common gnupg2 curl \
   libglapi-mesa libxext-dev libxdamage-dev libxshmfence-dev libxxf86vm-dev \
   libxcb-glx0 libxcb-dri2-0 libxcb-dri3-0 libxcb-present-dev \
   ca-certificates gosu tzdata libc6 libxdamage1 libxcb-present0 \
   libxcb-sync1 libxshmfence1 libxxf86vm1 python3-gpg python3-prometheus-client

# Create user and group
RUN mkdir -p /opt/dropbox \
 && useradd --home-dir /opt/dropbox --comment "Dropbox Daemon Account" --user-group --shell /usr/sbin/nologin dropbox \
 && chown -R dropbox:dropbox /opt/dropbox

# Install the Dropbox client into the image, outside the /opt/dropbox volume: a mounted
# volume would hide anything baked under /opt/dropbox, so the client lives at
# /opt/dropbox-client instead. Files stay root-owned so the dropbox user cannot tamper
# with the client.
RUN tmpdir="$(mktemp -d)" \
 && curl -fsSL -o "${tmpdir}/dropbox.tar.gz" "https://www.dropbox.com/download?plat=lnx.x86_64" \
 && tar xzf "${tmpdir}/dropbox.tar.gz" -C "${tmpdir}" --no-same-owner --no-same-permissions \
 && mv "${tmpdir}/.dropbox-dist" /opt/dropbox-client \
 && rm -rf "${tmpdir}" \
 && chmod -R a+rX /opt/dropbox-client \
 && find /opt/dropbox-client -type f -name "*.so" -exec chmod a+rx {} + \
 && curl -fsSL -o /opt/dropbox.py "https://www.dropbox.com/download?dl=packages/dropbox.py" \
 && printf '#!/bin/bash\npython3 /opt/dropbox.py "$@"\n' > /usr/bin/dropbox \
 && chmod +x /usr/bin/dropbox \
 # Dropbox's self-updater fills /tmp with large downloads; keep it read-only for others.
 # https://bbs.archlinux.org/viewtopic.php?id=191001
 && chmod go-w /tmp

# Create volumes
VOLUME ["/opt/dropbox"]

# Build arguments
ARG VCS_REF=main
ARG VERSION=""
ARG BUILD_DATE=""

# http://label-schema.org/rc1/
LABEL org.label-schema.schema-version "1.0"
LABEL org.label-schema.name           "Dropbox"
LABEL org.label-schema.version        "${VERSION}"
LABEL org.label-schema.build-date     "${BUILD_DATE}"
LABEL org.label-schema.description    "Standalone Dropbox client"
LABEL org.label-schema.vcs-url        "https://github.com/otherguy/docker-dropbox"
LABEL org.label-schema.vcs-ref        "${VCS_REF}"

# Configurable sleep delay
ENV POLLING_INTERVAL=5
# Possibility to skip permission check
ENV SKIP_SET_PERMISSIONS=false
# Possibility to enable Prometheus monitoring
ENV ENABLE_MONITORING=false
# Address the Prometheus endpoint listens on
ENV MONITORING_ADDRESS=0.0.0.0
# Port the Prometheus endpoint listens on
ENV MONITORING_PORT=8000

# Install init script and dropbox command line wrapper
COPY docker-entrypoint.sh /

# Install monitoring script
COPY monitoring.py /

# Set entrypoint and command
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/opt/dropbox-client/dropboxd"]
