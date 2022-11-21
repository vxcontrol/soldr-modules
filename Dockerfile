FROM minio/mc

FROM mysql:5.7-debian

COPY --from=0 /usr/bin/mc /usr/bin/mc

ARG VXVERSION=unknown

# Directory for Monitor service modules
RUN mkdir -p /opt/vxmodules/mon

# End User License Agreement for SOLDR modules
COPY LICENSE /opt/vxmodules/

# Entrypoint script
COPY startup.sh /opt/vxmodules/
# SQL file generator script
COPY gen_sql.py /opt/vxmodules/
# Content for test loading modules from S3
COPY syslog /opt/vxmodules/mon/syslog
COPY sysmon /opt/vxmodules/mon/sysmon
COPY file_remover /opt/vxmodules/mon/file_remover
COPY file_uploader /opt/vxmodules/mon/file_uploader
COPY proc_terminator /opt/vxmodules/mon/proc_terminator
COPY wineventlog /opt/vxmodules/mon/wineventlog
COPY file_reader /opt/vxmodules/mon/file_reader
COPY correlator /opt/vxmodules/mon/correlator
COPY correlator_linux /opt/vxmodules/mon/correlator_linux
COPY yara_scanner /opt/vxmodules/mon/yara_scanner
COPY lua_interpreter /opt/vxmodules/mon/lua_interpreter
COPY utils /opt/vxmodules/mon/utils
COPY config.json /opt/vxmodules/mon/

RUN chmod +x /opt/vxmodules/startup.sh
RUN chmod +x /opt/vxmodules/gen_sql.py

RUN \
  apt update && \
  apt install -y ca-certificates && \
  apt install -y jq && \
  apt install -y --no-install-recommends python3 python3-pip && \
  apt clean -y && \
  apt autoremove -y && \
  rm -rf /tmp/* /var/tmp/* && \
  rm -rf /var/lib/apt/lists/* && \
  echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf

RUN pip3 install pypika

WORKDIR /opt/vxmodules/mon/

# Generate new dump sql files
RUN python3 /opt/vxmodules/gen_sql.py /opt/vxmodules/

# Write version file
RUN echo ${VXVERSION} > /opt/vxmodules/version

ENTRYPOINT ["/opt/vxmodules/startup.sh"]
