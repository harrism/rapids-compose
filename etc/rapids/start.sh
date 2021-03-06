#!/usr/bin/env bash

set -Eeo pipefail

source /home/rapids/.bashrc

# - ensure conda's installed
# - ensure the rapids conda env is created/updated
source "$COMPOSE_HOME/etc/conda-install.sh" rapids

# If fresh conda env and cmd is build-rapids,
# do `clean-rapids` to delete build artifacts
[ "$FRESH_CONDA_ENV" == "1" ] \
 && [ "$(echo $@)" == "bash -c build-rapids" ] \
 && clean-rapids;

# activate the rapids conda environment
source activate rapids

# activate the rapids conda environment on bash login
echo "source /home/rapids/.bashrc && source activate rapids" > /home/rapids/.bash_login

RUN_CMD="$(echo $(eval "echo $@"))"

# Run with gosu because `docker-compose up` doesn't support the --user flag.
# see: https://github.com/docker/compose/issues/1532
if [ "$_UID:$_GID" != "$(id -u):$(id -g)" ]; then
    RUN_CMD="/usr/local/sbin/gosu $_UID:$_GID $RUN_CMD"
fi;

exec -l ${RUN_CMD}
