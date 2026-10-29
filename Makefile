.PHONY: up down preflight infra ssh-config kubeconfig secrets services
up: preflight infra ssh-config kubeconfig secrets services
preflight:
	scripts/preflight.sh
infra:
	scripts/infra.sh
ssh-config:
	scripts/ssh-config.sh
kubeconfig:
	scripts/kubeconfig.sh
secrets:
	scripts/secrets.sh
services:
	scripts/services.sh
down:
	scripts/down.sh
