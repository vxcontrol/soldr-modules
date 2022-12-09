FROM minio/mc as minio_client

FROM python:3.10-alpine

COPY --from=minio_client /usr/bin/mc /usr/bin/mc

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

RUN chmod +x /opt/vxmodules/startup.sh && \
    chmod +x /opt/vxmodules/gen_sql.py && \
    apk add --no-cache mysql-client bash jq && \
    echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf && \
    pip3 install pypika && \
    echo ${VXVERSION} > /opt/vxmodules/version

WORKDIR /opt/vxmodules/mon/

# Generate new dump sql files
RUN python3 /opt/vxmodules/gen_sql.py /opt/vxmodules/

ENTRYPOINT ["/opt/vxmodules/startup.sh"]
