FROM    openjdk:8-jre

ARG SOLR_DOWNLOAD_SERVER

RUN apt-get update && \
  apt-get -y install lsof && \
  rm -rf /var/lib/apt/lists/*

ENV SOLR_USER solr
ENV SOLR_UID 8983

RUN groupadd -r -g $SOLR_UID $SOLR_USER && \
  useradd -r -u $SOLR_UID -G $SOLR_USER -g $SOLR_USER $SOLR_USER

ENV SOLR_VERSION 6.6.0
ENV SOLR_URL ${SOLR_DOWNLOAD_SERVER:-https://archive.apache.org/dist/lucene/solr}/$SOLR_VERSION/solr-$SOLR_VERSION.tgz
ENV SOLR_SHA256 6b1d1ed0b74aef320633b40a38a790477e00d75b56b9cdc578533235315ffa1e
ENV SOLR_KEYS 2085660D9C1FCCACC4A479A3BF160FF14992A24C

RUN set -e; for key in $SOLR_KEYS; do \
    found=''; \
    for server in \
      ha.pool.sks-keyservers.net \
      hkp://keyserver.ubuntu.com:80 \
      hkp://p80.pool.sks-keyservers.net:80 \
      pgp.mit.edu \
    ; do \
      echo "  trying $server for $key"; \
      gpg --keyserver "$server" --keyserver-options timeout=10 --recv-keys "$key" && found=yes && break; \
    done; \
    test -z "$found" && echo >&2 "error: failed to fetch $key from several disparate servers -- network issues?" && exit 1; \
  done; \
  exit 0

RUN mkdir -p /opt/solr && \
  wget -nv $SOLR_URL -O /opt/solr.tgz && \
  wget -nv $SOLR_URL.asc -O /opt/solr.tgz.asc && \
  echo "$SOLR_SHA256 */opt/solr.tgz" | sha256sum -c - && \
  (>&2 ls -l /opt/solr.tgz /opt/solr.tgz.asc) && \
  gpg --batch --verify /opt/solr.tgz.asc /opt/solr.tgz && \
  tar -C /opt/solr --extract --file /opt/solr.tgz --strip-components=1 && \
  rm /opt/solr.tgz* && \
  rm -Rf /opt/solr/docs/ && \
  mkdir -p /opt/solr/server/solr/lib /opt/solr/server/solr/mycores && \
  sed -i -e 's/#SOLR_PORT=8983/SOLR_PORT=8983/' /opt/solr/bin/solr.in.sh && \
  sed -i -e '/-Dsolr.clustering.enabled=true/ a SOLR_OPTS="$SOLR_OPTS -Dsun.net.inetaddr.ttl=60 -Dsun.net.inetaddr.negative.ttl=60"' /opt/solr/bin/solr.in.sh && \
  chown -R $SOLR_USER:$SOLR_USER /opt/solr && \
  mkdir /docker-entrypoint-initdb.d /opt/docker-solr/

COPY scripts /opt/docker-solr/scripts
RUN chown -R $SOLR_USER:$SOLR_USER /opt/docker-solr

ENV PATH /opt/solr/bin:/opt/docker-solr/scripts:$PATH

COPY ./config /tmp/solr-drupal-config

RUN mkdir -p /opt/solr/server/solr/collection1/conf && \
    mkdir -p /opt/solr/server/solr/collection1/data && \
    cd /tmp/solr-drupal-config && cp -f * /opt/solr/server/solr/collection1/conf/

RUN mkdir -p /opt/solr/server/solr/collection2/conf && \
    mkdir -p /opt/solr/server/solr/collection2/data && \
    cd /tmp/solr-drupal-config && cp -f * /opt/solr/server/solr/collection2/conf/

COPY ./core1.properties /tmp/core1.properties
RUN cp -f /tmp/core1.properties /opt/solr/server/solr/collection1/core.properties

COPY ./core2.properties /tmp/core2.properties
RUN cp -f /tmp/core2.properties /opt/solr/server/solr/collection2/core.properties


RUN chown -R solr:solr /opt/solr/server/solr
RUN chmod +x /opt/docker-solr/scripts/*

EXPOSE 8983
WORKDIR /opt/solr
USER $SOLR_USER

ENTRYPOINT ["/opt/docker-solr/scripts/docker-entrypoint.sh"]
CMD ["solr-foreground"]
