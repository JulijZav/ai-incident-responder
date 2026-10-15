CLUSTER				:= incident-lab
NAMESPACE			:= task-tracker
RELEASE				:= tt
CHART				:= charts/task-tracker

TASK_TRACKER_DIR	?= ../task-tracker
APP_VERSION 		?= 0.1.0
IMAGE 				?= task-tracker:$(APP_VERSION)

.PHONY: help up down cluster image deploy status

help: ## Show available commands
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-8s %s\n", $$1, $$2}'

up: cluster image deploy ## Create everything from scratch

down: ## Delete the cluster, includin database data!
	k3d cluster delete $(CLUSTER)

cluster: ## Create the k3d cluster if it does not exist
	@if k3d cluster get $(CLUSTER) > /dev/null 2>&1; then \
		echo "Cluster $(CLUSTER) already exists."; \
	else \
	  k3d cluster create --config cluster/k3d-config.yaml; \
	fi

image: ## Build the task-tracker image and import it into the cluster
	docker build -t $(IMAGE) $(TASK_TRACKER_DIR)
	k3d image import $(IMAGE) -c $(CLUSTER)

.env:
	@echo "PG_PASSWORD=$$(openssl rand -hex 16)" > .env
	@echo "Created .env with a new password"

deploy: .env ## Install or upgrade task-tracker
	. ./.env && helm upgrade --install $(RELEASE) $(CHART) \
		--namespace $(NAMESPACE) --create-namespace \
		--set postgres.password=$$PG_PASSWORD \
		--set api.image.tag=$(APP_VERSION) \
		--wait --timeout 5m

status: ## Show nodes, pods and deploy history
	kubectl get nodes
	kubectl get pods -n $(NAMESPACE)
	helm history $(RELEASE) -n $(NAMESPACE)