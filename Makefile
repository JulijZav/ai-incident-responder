CLUSTER				:= incident-lab
NAMESPACE			:= task-tracker
RELEASE				:= tt
CHART				:= charts/task-tracker

MONITORING_NS		:= monitoring
KPS_RELEASE			:= kps
KPS_VERSION			?= 92.10.1

TASK_TRACKER_DIR	?= ../task-tracker
APP_VERSION 		?= 0.2.1
IMAGE 				?= task-tracker:$(APP_VERSION)

.PHONY: help up down cluster image deploy status observability grafana prometheus

help: ## Show available commands
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-8s %s\n", $$1, $$2}'

up: cluster observability image deploy ## Create everything from scratch

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
	@echo "GRAFANA_PASSWORD=$$(openssl rand -hex 12)" >> .env
	@echo "Created .env with new passwords"

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

observability: .env ## Install the monitoring stack (Prometheus, Grafana, Alertmanager)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	. ./.env && helm upgrade --install $(KPS_RELEASE) prometheus-community/kube-prometheus-stack \
		--version $(KPS_VERSION) \
		--namespace $(MONITORING_NS) --create-namespace \
		-f observability/kube-prometheus-stack-values.yaml \
		--set grafana.adminPassword=$$GRAFANA_PASSWORD \
		--wait --timeout 10m

grafana: ## Open Grafana on http://localhost:3000 (user: admin)
	kubectl port-forward -n $(MONITORING_NS) svc/$(KPS_RELEASE)-grafana 3000:80

prometheus: ## Open Prometheus on http://localhost:9090
	kubectl port-forward -n $(MONITORING_NS) svc/$(KPS_RELEASE)-prometheus 9090:9090