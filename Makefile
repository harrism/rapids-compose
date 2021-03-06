SHELL := /bin/bash
PLATFORM := $(shell uname)
UID.Linux := $(shell id -u $$USER)
GID.Linux := $(shell id -g $$USER)
UID.Darwin := $(shell id -u $$USER)
GID.Darwin := $(shell id -g $$USER)
UID := $(or ${UID.${PLATFORM}}, 1000)
GID := $(or ${GID.${PLATFORM}}, 1000)

# define a "make in quiet mode" shortcut to hide
# superfluous entering/exiting directory messages
MAKE_Q := $(MAKE) --no-print-directory

DEFAULT_CUDA_VERSION := 10.0
DEFAULT_PYTHON_VERSION := 3.7
DEFAULT_LINUX_VERSION := ubuntu18.04
DEFAULT_RAPIDS_NAMESPACE := $(shell echo $$USER)
DEFAULT_RAPIDS_VERSION := $(shell RES="" \
 && [ -z "$$RES" ] && RES=$$(cd ../cudf 2>/dev/null && git describe --abbrev=0 --tags) || true \
 && [ -z "$$RES" ] && [ -n `which curl` ] && [ -n `which jq` ] && RES=$$(curl -s https://api.github.com/repos/rapidsai/cudf/tags | jq -e -r ".[].name" 2>/dev/null | head -n1) || true \
 && echo $${RES:-"latest"})

.PHONY: init rapids notebooks rapids.build rapids.run rapids.exec rapids.logs rapids.cudf.run rapids.cudf.pytest rapids.cudf.pytest.debug notebooks.build notebooks.run notebooks.up notebooks.exec notebooks.logs dind dc dc.up dc.run dc.dind dc.exec dc.logs dc.apt.cacher.up

.SILENT: init rapids notebooks rapids.build rapids.run rapids.exec rapids.logs rapids.cudf.run rapids.cudf.pytest rapids.cudf.pytest.debug notebooks.build notebooks.run notebooks.up notebooks.exec notebooks.logs dind dc dc.up dc.run dc.dind dc.exec dc.logs dc.apt.cacher.up

all: rapids

rapids: rapids.build
	@$(MAKE_Q) dc.run svc="rapids" cmd_args="-u $(UID):$(GID)" svc_args="bash -c 'build-rapids'"

notebooks: notebooks.build
	@$(MAKE_Q) dc.run svc="notebooks" cmd_args="-u $(UID):$(GID)" svc_args="echo 'notebooks build complete'"

rapids.build:
	@$(MAKE_Q) dc.build svc="rapids"

rapids.run: args ?=
rapids.run: cmd_args ?=
rapids.run: work_dir ?= /rapids
rapids.run: dc.apt.cacher.up
	@$(MAKE_Q) dc.run svc="rapids" svc_args="$(args)" cmd_args="-u $(UID):$(GID) -w $(work_dir) $(cmd_args)"

rapids.exec: args ?=
rapids.exec:
	@$(MAKE_Q) dc.exec svc="rapids" svc_args="$(args)"

rapids.logs: args ?=
rapids.logs: cmd_args ?= -f
rapids.logs:
	@$(MAKE_Q) dc.logs svc="rapids" svc_args="$(args)" cmd_args="$(cmd_args)"

rapids.cudf.run: args ?=
rapids.cudf.run: cmd_args ?=
rapids.cudf.run: work_dir ?= /rapids/cudf
rapids.cudf.run:
	@$(MAKE_Q) rapids.run work_dir="$(work_dir)" args="$(args)" cmd_args="$(cmd_args)"

rapids.cudf.pytest: args ?= -v -x
rapids.cudf.pytest:
	@$(MAKE_Q) rapids.cudf.run work_dir="/rapids/cudf/python/cudf" args="pytest $(args)"

rapids.cudf.pytest.debug: args ?= -v -x
rapids.cudf.pytest.debug:
	@$(MAKE_Q) rapids.cudf.run work_dir="/rapids/cudf/python/cudf" args="pytest-debug $(args)"

rapids.cudf.lint:
	@$(MAKE_Q) rapids.cudf.run args="bash -c 'lint-cudf-python'"

notebooks.build:
	@$(MAKE_Q) dc.build svc="notebooks"

notebooks.run: args ?=
notebooks.run: cmd_args ?=
notebooks.run:
	@$(MAKE_Q) dc.run svc="notebooks" svc_args="$(args)" cmd_args="-u $(UID):$(GID) $(cmd_args)"

notebooks.up: args ?=
notebooks.up: cmd_args ?= -d
notebooks.up:
	@$(MAKE_Q) dc.up svc="notebooks" svc_args="$(args)" cmd_args="$(cmd_args)"

notebooks.exec: args ?=
notebooks.exec: cmd_args ?=
notebooks.exec:
	@$(MAKE_Q) dc.exec svc="notebooks" svc_args="$(args)" cmd_args="-u $(UID):$(GID) $(cmd_args)"

notebooks.logs: args ?=
notebooks.logs: cmd_args ?= -f
notebooks.logs:
	@$(MAKE_Q) dc.logs svc="notebooks" svc_args="$(args)" cmd_args="$(cmd_args)"

dc.apt.cacher.up:
	@$(MAKE_Q) dc.up svc="apt-cacher-ng" cmd_args="-d"

dc.build: svc ?=
dc.build: svc_args ?=
dc.build: cmd_args ?= -f
dc.build: file ?= docker-compose.yml
dc.build: dc.apt.cacher.up
	@$(MAKE_Q) dc.dind cmd="build"

dc.up: svc ?=
dc.up: svc_args ?=
dc.up: cmd_args ?=
dc.up: file ?= docker-compose.yml
dc.up:
	@$(MAKE_Q) dc cmd="up"

dc.run: svc ?=
dc.run: svc_args ?=
dc.run: cmd_args ?=
dc.run: file ?= docker-compose.yml
dc.run:
	@$(MAKE_Q) dc cmd="run" cmd_args="--rm $(cmd_args)"

dc.exec: svc ?=
dc.exec: svc_args ?=
dc.exec: cmd_args ?=
dc.exec: file ?= docker-compose.yml
dc.exec:
	@$(MAKE_Q) dc cmd="exec"

dc.logs: svc ?=
dc.logs: svc_args ?=
dc.logs: cmd_args ?= -f
dc.logs: file ?= docker-compose.yml
dc.logs:
	@$(MAKE_Q) dc cmd="logs"

# Run docker-compose
dc: svc ?=
dc: args ?=
dc: cmd ?= build
dc: svc_args ?=
dc: cmd_args ?=
dc: file ?= docker-compose.yml
dc: 
	set -a && . .env && set +a && \
	env	_UID=$${UID:-$(UID)} \
		_GID=$${GID:-$(GID)} \
		RAPIDS_HOME="$$RAPIDS_HOME" \
		COMPOSE_HOME="$$COMPOSE_HOME" \
		CUDA_VERSION=$${CUDA_VERSION:-$(DEFAULT_CUDA_VERSION)} \
		LINUX_VERSION=$${LINUX_VERSION:-$(DEFAULT_LINUX_VERSION)} \
		PYTHON_VERSION=$${PYTHON_VERSION:-$(DEFAULT_PYTHON_VERSION)} \
		RAPIDS_VERSION=$${RAPIDS_VERSION:-$(DEFAULT_RAPIDS_VERSION)} \
		RAPIDS_NAMESPACE=$${RAPIDS_NAMESPACE:-$(DEFAULT_RAPIDS_NAMESPACE)} \
		docker-compose -f $(file) $(cmd) $(cmd_args) $(svc) $(svc_args)

init:
	export CODE_REPOS="rmm cudf cuml cugraph" && \
	export ALL_REPOS="$$CODE_REPOS notebooks notebooks-contrib" && \
	export PYTHON_DIRS="rmm/python \
						cuml/python \
						cugraph/python \
						cudf/python/cudf \
						cudf/python/nvstrings \
						cudf/python/dask_cudf" && \
	touch ./etc/rapids/.bash_history && \
	bash -i ./scripts/01-install-dependencies.sh && \
	bash -i ./scripts/02-create-compose-env.sh && \
	bash -i ./scripts/03-create-vscode-workspace.sh && \
	bash -i ./scripts/04-clone-rapids-repositories.sh && \
	bash -i ./scripts/05-setup-c++-intellisense.sh && \
	bash -i ./scripts/06-setup-python-intellisense.sh && \
	[ -n "$$NEEDS_REBOOT" ] && echo "Installed new dependencies, please reboot to continue." \
	                || true && echo "RAPIDS workspace init success!"

# Run a docker container that prints the build context size and top ten largest folders
dc.print_build_context:
	@$(MAKE_Q) dc.dind cmd="print_build_context"

# Build the docker-in-docker container
dind:
	set -a && . .env && set +a && \
	export RAPIDS_VERSION=$${RAPIDS_VERSION:-$(DEFAULT_RAPIDS_VERSION)} && \
	export RAPIDS_NAMESPACE=$${RAPIDS_NAMESPACE:-$(DEFAULT_RAPIDS_NAMESPACE)} && \
	docker build -q \
		--build-arg RAPIDS_HOME="$$RAPIDS_HOME" \
		--build-arg COMPOSE_HOME="$$COMPOSE_HOME" \
		-t "$$RAPIDS_NAMESPACE/rapids/dind:$$RAPIDS_VERSION" \
		-f dockerfiles/dind.Dockerfile .

# Run docker-compose inside the docker-in-docker container
dc.dind: svc ?=
dc.dind: args ?=
dc.dind: cmd ?= build
dc.dind: svc_args ?=
dc.dind: cmd_args ?=
dc.dind: file ?= docker-compose.yml
dc.dind: dind
	set -a && . .env && set +a && \
	export RAPIDS_VERSION=$${RAPIDS_VERSION:-$(DEFAULT_RAPIDS_VERSION)} && \
	export RAPIDS_NAMESPACE=$${RAPIDS_NAMESPACE:-$(DEFAULT_RAPIDS_NAMESPACE)} && \
	docker run -it --rm --net=host --entrypoint "$$COMPOSE_HOME/etc/dind/$(cmd).sh" \
		-v "$$COMPOSE_HOME:$$COMPOSE_HOME" \
		-v "$$RAPIDS_HOME/rmm:$$RAPIDS_HOME/rmm" \
		-v "$$RAPIDS_HOME/cudf:$$RAPIDS_HOME/cudf" \
		-v "$$RAPIDS_HOME/cugraph:$$RAPIDS_HOME/cugraph" \
		-v "$$RAPIDS_HOME/notebooks:$$RAPIDS_HOME/notebooks" \
		-v "$$RAPIDS_HOME/notebooks-contrib:$$RAPIDS_HOME/notebooks-contrib" \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-e _UID=$${UID:-$(UID)} \
		-e _GID=$${GID:-$(GID)} \
		-e RAPIDS_HOME="$$RAPIDS_HOME" \
		-e CUDA_VERSION=$${CUDA_VERSION:-$(DEFAULT_CUDA_VERSION)} \
		-e LINUX_VERSION=$${LINUX_VERSION:-$(DEFAULT_LINUX_VERSION)} \
		-e PYTHON_VERSION=$${PYTHON_VERSION:-$(DEFAULT_PYTHON_VERSION)} \
		-e RAPIDS_VERSION=$${RAPIDS_VERSION:-$(DEFAULT_RAPIDS_VERSION)} \
		-e RAPIDS_NAMESPACE=$${RAPIDS_NAMESPACE:-$(DEFAULT_RAPIDS_NAMESPACE)} \
		"$$RAPIDS_NAMESPACE/rapids/dind:$$RAPIDS_VERSION" $(file) $(cmd_args) $(svc) $(svc_args)
