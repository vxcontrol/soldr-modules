#!/bin/bash

export LANG=C.UTF-8

# Test connection to minio
while true; do
    mc config host add vxm "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" 2>&1 1>/dev/null
    if [ $? -eq 0 ]; then
        echo "connect to minio was successful"
        break
    fi
    echo "failed to connect to minio"
    sleep 1
done

mc mb --ignore-existing vxm/$MINIO_BUCKET_NAME

MODELS=$(jq -r '.[] | (.name + "/" + (.version.major|tostring) + "." + (.version.minor|tostring) + "." + (.version.patch|tostring))' config.json | uniq)
for dir in $MODELS; do
    echo "remove module version $dir from global bucket"
    mc rm --recursive --force vxm/$MINIO_BUCKET_NAME/${dir}
done
echo "remove utils from global bucket"
mc rm --recursive --force vxm/$MINIO_BUCKET_NAME/utils
echo "copy modules to global bucket"
mc cp --recursive /opt/vxmodules/mon/ vxm/$MINIO_BUCKET_NAME


# Test connection to mysql
while true; do
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -e ";" 2>&1 1>/dev/null
    if [ $? -eq 0 ]; then
        echo "connect to mysql was successful"
        break
    fi
    echo "failed to connect to mysql"
    sleep 1
done

# Waiting migrations from vxapi into mysql
GET_MIGRATION="SELECT count(*) FROM gorp_migrations WHERE id = '0001_initial.sql';"
while true; do
    MIGRATION=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -Nse "$GET_MIGRATION" 2>/dev/null)
    if [[ $? -eq 0 && $MIGRATION -eq 1 ]]; then
        echo "vxapi migrations was found"
        break
    fi
    echo "failed to update global modules table"
    sleep 1
done

# update modules base columns into global DB
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < /opt/vxmodules/dump_global.sql
echo "base updating of modules into global DB complete"
mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" < /opt/vxmodules/dump_global_sec_cfg.sql
echo "updating of modules secure config into global DB was complete"

echo "done"

GET_MODULES="SELECT name from modules;"
MODULES=$(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -Nse "$GET_MODULES" 2>/dev/null)
echo "List of modules in database: $MODULES"


sleep infinity
