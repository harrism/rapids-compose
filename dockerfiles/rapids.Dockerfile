ARG CUDA_VERSION=10.0
ARG RAPIDS_VERSION=latest
ARG RAPIDS_NAMESPACE=anon
ARG LINUX_VERSION=ubuntu16.04
ARG CUDA_SHORT_VERSION=${CUDA_VERSION}
FROM nvidia/cuda:${CUDA_VERSION}-devel-${LINUX_VERSION}

ARG CUDA_SHORT_VERSION

ARG GCC_VERSION=5
ARG CXX_VERSION=5
ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'Acquire::HTTP::Proxy "http://172.17.0.1:3142";' >> /etc/apt/apt.conf.d/01proxy \
 && echo 'Acquire::HTTPS::Proxy "false";' >> /etc/apt/apt.conf.d/01proxy \
 && apt update -y --fix-missing && apt upgrade -y \
 && apt install -y software-properties-common \
 && add-apt-repository -y ppa:git-core/ppa \
 && apt update -y \
 && apt install -y \
    git sudo \
    curl wget \
    jq ed vim nano \
    # Need tzdata for the pyarrow<->ORC tests
    tzdata \
    apt-utils \
    ninja-build \
    libboost-all-dev \
    gcc-${GCC_VERSION} \
    g++-${CXX_VERSION} \
    python3 python3-pip \
    apt-transport-https \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG UID=1000
ARG GID=1000
ENV _UID=${UID}
ENV _GID=${GID}
ARG GOSU_VERSION=1.11
ARG TINI_VERSION=v0.18.0
ARG CCACHE_VERSION=3.7.7
ENV CCACHE_VERSION=${CCACHE_VERSION}

ARG PYTHON_VERSION=3.7
ENV PYTHON_VERSION="$PYTHON_VERSION"
ENV CUDA_SHORT_VERSION="$CUDA_SHORT_VERSION"
ENV CC="/usr/bin/gcc-$GCC_VERSION"
ENV CXX="/usr/bin/g++-$CXX_VERSION"

ARG PTVSD_LOG_DIR=/var/log/ptvsd
ENV PTVSD_LOG_DIR="$PTVSD_LOG_DIR"

ARG RAPIDS_HOME
ARG COMPOSE_HOME
ENV RAPIDS_HOME="$RAPIDS_HOME"
ENV COMPOSE_HOME="$COMPOSE_HOME"
ENV CONDA_HOME="$COMPOSE_HOME/etc/conda/cuda_$CUDA_SHORT_VERSION"
ENV RMM_HOME="$RAPIDS_HOME/rmm"
ENV CUDF_HOME="$RAPIDS_HOME/cudf"
ENV CUML_HOME="$RAPIDS_HOME/cuml"
ENV CUGRAPH_HOME="$RAPIDS_HOME/cugraph"
ENV NOTEBOOKS_HOME="$RAPIDS_HOME/notebooks"
ENV NOTEBOOKS_EXTENDED_HOME="$RAPIDS_HOME/notebooks-contrib"

RUN curl -s -L https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/ccache-${CCACHE_VERSION}.tar.gz -o ccache-${CCACHE_VERSION}.tar.gz \
 && tar -xvzf ccache-${CCACHE_VERSION}.tar.gz && cd ccache-${CCACHE_VERSION} \
 && ./configure && make install -j && cd - && rm -rf ./ccache-${CCACHE_VERSION} ./ccache-${CCACHE_VERSION}.tar.gz \
 && curl -s -L https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini -o /usr/bin/tini && chmod +x /usr/bin/tini \
 # Add gosu so we can run our apps as a non-root user
 # https://denibertovic.com/posts/handling-permissions-with-docker-volumes/
 && curl -s -L https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64 -o /usr/local/sbin/gosu && chmod +x /usr/local/sbin/gosu \
 && mkdir -p /var/log "$PTVSD_LOG_DIR" "$RAPIDS_HOME" "$CONDA_HOME" \
             /home/rapids /home/rapids/.conda /home/rapids/notebooks \
 # Symlink to root so we have an easy entrypoint from external scripts
 && ln -s "$RAPIDS_HOME" /rapids \
 # Create a rapids user with the same GID/UID as your outside OS user,
 # so you own files created by the container when using volume mounts.
 && groupadd -g ${GID} rapids && useradd -u ${UID} -g rapids \
    # 1. Set up a rapids home directory
    # 2. Add this user to the tty group
    # 3. Assign bash as the login shell
    -d /home/rapids -G tty -G sudo -s /bin/bash rapids \
 && echo rapids:rapids | chpasswd \
 && chmod 0777 /tmp \
 && chown -R ${_UID}:${_GID} /home/rapids "$CONDA_HOME" \
 && chmod -R 0755 /var/log /home/rapids "$CONDA_HOME" "$PTVSD_LOG_DIR" \
 && bash -c "echo -e '#!/bin/bash -e\n\
exec \"$COMPOSE_HOME/etc/rapids/start.sh\" \"\$@\"\n\
'" > /entrypoint.sh \
 && touch /home/rapids/.bashrc && touch /home/rapids/.bash_history \
 && chown ${_UID}:${_GID} /entrypoint.sh /home/rapids/.bashrc /home/rapids/.bash_history \
 && chmod +x /entrypoint.sh

# avoid "OSError: library nvvm not found" error
ENV CUDA_HOME="/usr/local/cuda-$CUDA_SHORT_VERSION"

RUN pip3 install --no-cache-dir conda-merge==0.1.5

ENV PATH="$CONDA_HOME/bin:$CUDA_HOME/bin:$PATH:/usr/local/bin:/usr/bin"
ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$CUDA_HOME/lib64"
ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib"
ENV LD_LIBRARY_PATH="$CONDA_HOME/lib:$LD_LIBRARY_PATH"
ENV LD_LIBRARY_PATH="$CONDA_HOME/envs/rapids/lib:$LD_LIBRARY_PATH"

# Expose VSCode debugger port
EXPOSE 5678

ARG BUILD_TESTS="OFF"
ENV BUILD_TESTS="$BUILD_TESTS"

ARG BUILD_BENCHMARKS="OFF"
ENV BUILD_BENCHMARKS="$BUILD_BENCHMARKS"

ARG CMAKE_BUILD_TYPE="Release"
ENV CMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE"

ARG FRESH_CONDA_ENV=0
ENV FRESH_CONDA_ENV=$FRESH_CONDA_ENV

WORKDIR $RAPIDS_HOME

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

CMD ["bash"]
