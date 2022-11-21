# SOLDR modules repository

## Using

There is using next environment variables to run the container:

* `DB_HOST` - Global MySQL IP address or domain
* `DB_PORT` - Global MySQL TCP port to connect
* `DB_USER` - Global MySQL username to connect
* `DB_PASS` - Global MySQL password to connect
* `DB_NAME` - Global MySQL database name to connect
* `MINIO_ENDPOINT` - URL to connect to Minio S3 storage (including port and schema)
* `MINIO_ACCESS_KEY` - Access key to connect to Minio S3 storage
* `MINIO_SECRET_KEY` - Secret key to connect to Minio S3 storage
* `MINIO_BUCKET_NAME` - Global S3 bucket name to connect and copy modules files

Command to build image:

`docker build -t local/modules .`

## Simple docker_env file

Command to run container (to remote services):

`docker run --add-host mysql.local:10.0.0.1 --add-host minio.local:10.0.0.2 --rm --env-file docker_env.list -ti local/modules`

Or link to local running containers:

`docker run --link=vx_mysql:mysql.local --link=vx_minio:minio.local --net soldr_vx-stand --rm --env-file docker_env.list -ti local/modules`

File docker_env.list by default:

```
DB_HOST=mysql.local
DB_PORT=3306
DB_USER=vxcontrol
DB_PASS=password
DB_NAME=vx_global
MINIO_ENDPOINT=http://minio.local:9000
MINIO_ACCESS_KEY=accesskey
MINIO_SECRET_KEY=secretkey
MINIO_BUCKET_NAME=soldr-modules
```

## Simple script file export environment variables to current bash session

Command to run container:

`. ./env.sh`

File env.sh by default:

```
export DB_HOST=mysql.local
export DB_PORT=3306
export DB_USER=vxcontrol
export DB_PASS=password
export DB_NAME=vx_global
export MINIO_ENDPOINT=http://minio.local:9000
export MINIO_ACCESS_KEY=accesskey
export MINIO_SECRET_KEY=secretkey
export MINIO_BUCKET_NAME=soldr-modules
```
