# Variables
DOCKER_REGISTRY=langgenius
WEB_IMAGE=$(DOCKER_REGISTRY)/dify-web
API_IMAGE=$(DOCKER_REGISTRY)/dify-api
VERSION=latest

# Default target - show help
.DEFAULT_GOAL := help

# Backend Development Environment Setup
.PHONY: dev-setup prepare-docker prepare-web prepare-api

# Dev setup target
dev-setup: prepare-docker prepare-web prepare-api
	@echo "✅ Backend development environment setup complete!"

# Step 1: Prepare Docker middleware
prepare-docker:
	@echo "🐳 Setting up Docker middleware..."
	@cp -n docker/middleware.env.example docker/middleware.env 2>/dev/null || echo "Docker middleware.env already exists"
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev up -d
	@echo "✅ Docker middleware started"

# Step 2: Prepare web environment
prepare-web:
	@echo "🌐 Setting up web environment..."
	@cp -n web/.env.example web/.env 2>/dev/null || echo "Web .env already exists"
	@cd web && pnpm install
	@echo "✅ Web environment prepared (not started)"

# Step 3: Prepare API environment
prepare-api:
	@echo "🔧 Setting up API environment..."
	@cp -n api/.env.example api/.env 2>/dev/null || echo "API .env already exists"
	@cd api && uv sync --dev
	@cd api && uv run flask db upgrade
	@echo "✅ API environment prepared (not started)"

# Clean dev environment
dev-clean:
	@echo "⚠️  Stopping Docker containers..."
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev down
	@echo "🗑️  Removing volumes..."
	@rm -rf docker/volumes/db
	@rm -rf docker/volumes/redis
	@rm -rf docker/volumes/plugin_daemon
	@rm -rf docker/volumes/weaviate
	@rm -rf api/storage
	@echo "✅ Cleanup complete"

# Podman Middleware Commands
podman-up:
	@echo "🐳 Starting Podman middleware..."
	@cp -n docker/middleware.env.example docker/middleware.env 2>/dev/null || true
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev up -d
	@echo "✅ Podman middleware started"

podman-down:
	@echo "🐳 Stopping Podman middleware..."
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev down
	@echo "✅ Podman middleware stopped"

podman-restart:
	@echo "🐳 Restarting Podman middleware..."
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev restart
	@echo "✅ Podman middleware restarted"

podman-logs:
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev logs -f

podman-ps:
	@cd docker && podman-compose -f podman-compose.middleware.yaml --env-file middleware.env -p dify-middlewares-dev ps

# Run individual services
run-api:
	@echo "🚀 Starting API server..."
	@cd api && uv run flask run --host 0.0.0.0 --port 5001

run-worker:
	@echo "🚀 Starting Celery worker..."
	@cd api && uv run celery -A app.celery worker -P gevent -c 1 --loglevel INFO -Q dataset,generation,mail,ops_trace,app_deletion

run-web:
	@echo "🚀 Starting Web server..."
	@cd web && pnpm dev

# Run full solution (local dev - middleware + local API/Web)
run-all:
	@echo "🚀 Starting Dify full solution (dev mode)..."
	@$(MAKE) podman-up
	@echo "⏳ Waiting for middleware to be ready..."
	@sleep 5
	@echo "📝 Starting API and Web in background..."
	@cd api && uv run flask run --host 0.0.0.0 --port 5001 &
	@cd web && pnpm dev &
	@echo "✅ Dify solution started!"
	@echo "   API: http://localhost:5001"
	@echo "   Web: http://localhost:3000"

# Dify Full Solution with Official Images (Production-like)
dify-up:
	@echo "🚀 Starting Dify full solution with official images..."
	@cp -n docker/middleware.env.example docker/middleware.env 2>/dev/null || true
	@mkdir -p docker/.docker-data/sandbox/conf
	@cp -n docker/volumes/sandbox/conf/config.yaml docker/.docker-data/sandbox/conf/ 2>/dev/null || true
	@cd docker && podman-compose -f podman-compose.yml --env-file middleware.env -p dify up -d || true
	@echo "⏳ Waiting for services to be ready..."
	@sleep 3
	@podman start dify_nginx_1 2>/dev/null || true
	@echo "✅ Dify solution started!"
	@echo "   Web UI: http://localhost:15678"

dify-down:
	@echo "🛑 Stopping Dify full solution..."
	@cd docker && podman-compose -f podman-compose.yml --env-file middleware.env -p dify down
	@echo "✅ Dify solution stopped"

dify-restart:
	@echo "🔄 Restarting Dify full solution..."
	@cd docker && podman-compose -f podman-compose.yml --env-file middleware.env -p dify restart
	@echo "✅ Dify solution restarted"

dify-logs:
	@cd docker && podman-compose -f podman-compose.yml --env-file middleware.env -p dify logs -f

dify-ps:
	@cd docker && podman-compose -f podman-compose.yml --env-file middleware.env -p dify ps

dify-pull:
	@echo "📥 Pulling latest Dify images..."
	@cd docker && podman-compose -f podman-compose.yml --env-file middleware.env -p dify pull
	@echo "✅ Images pulled"

# Backend Code Quality Commands
format:
	@echo "🎨 Running ruff format..."
	@uv run --project api --dev ruff format ./api
	@echo "✅ Code formatting complete"

check:
	@echo "🔍 Running ruff check..."
	@uv run --project api --dev ruff check ./api
	@echo "✅ Code check complete"

lint:
	@echo "🔧 Running ruff format, check with fixes, import linter, and dotenv-linter..."
	@uv run --project api --dev sh -c 'ruff format ./api && ruff check --fix ./api'
	@uv run --directory api --dev lint-imports
	@uv run --project api --dev dotenv-linter ./api/.env.example ./web/.env.example
	@echo "✅ Linting complete"

type-check:
	@echo "📝 Running type check with basedpyright..."
	@uv run --directory api --dev basedpyright
	@echo "✅ Type check complete"

test:
	@echo "🧪 Running backend unit tests..."
	@uv run --project api --dev dev/pytest/pytest_unit_tests.sh
	@echo "✅ Tests complete"

# Build Docker images
build-web:
	@echo "Building web Docker image: $(WEB_IMAGE):$(VERSION)..."
	docker build -t $(WEB_IMAGE):$(VERSION) ./web
	@echo "Web Docker image built successfully: $(WEB_IMAGE):$(VERSION)"

build-api:
	@echo "Building API Docker image: $(API_IMAGE):$(VERSION)..."
	docker build -t $(API_IMAGE):$(VERSION) ./api
	@echo "API Docker image built successfully: $(API_IMAGE):$(VERSION)"

# Push Docker images
push-web:
	@echo "Pushing web Docker image: $(WEB_IMAGE):$(VERSION)..."
	docker push $(WEB_IMAGE):$(VERSION)
	@echo "Web Docker image pushed successfully: $(WEB_IMAGE):$(VERSION)"

push-api:
	@echo "Pushing API Docker image: $(API_IMAGE):$(VERSION)..."
	docker push $(API_IMAGE):$(VERSION)
	@echo "API Docker image pushed successfully: $(API_IMAGE):$(VERSION)"

# Build all images
build-all: build-web build-api

# Push all images
push-all: push-web push-api

build-push-api: build-api push-api
build-push-web: build-web push-web

# Build and push all images
build-push-all: build-all push-all
	@echo "All Docker images have been built and pushed."

# Help target
help:
	@echo "Development Setup Targets:"
	@echo "  make dev-setup      - Run all setup steps for backend dev environment"
	@echo "  make prepare-docker - Set up Docker middleware"
	@echo "  make prepare-web    - Set up web environment"
	@echo "  make prepare-api    - Set up API environment"
	@echo "  make dev-clean      - Stop Docker middleware and clean volumes"
	@echo ""
	@echo "Podman Middleware:"
	@echo "  make podman-up      - Start Podman middleware containers"
	@echo "  make podman-down    - Stop Podman middleware containers"
	@echo "  make podman-restart - Restart Podman middleware containers"
	@echo "  make podman-logs    - Follow Podman middleware logs"
	@echo "  make podman-ps      - Show Podman middleware container status"
	@echo ""
	@echo "Run Services (Dev Mode):"
	@echo "  make run-api        - Start API server (Flask)"
	@echo "  make run-worker     - Start Celery worker"
	@echo "  make run-web        - Start Web server (Next.js)"
	@echo "  make run-all        - Start dev solution (middleware + local API + Web)"
	@echo ""
	@echo "Dify Full Solution (Official Images):"
	@echo "  make dify-up        - Start full Dify with official images"
	@echo "  make dify-down      - Stop full Dify solution"
	@echo "  make dify-restart   - Restart full Dify solution"
	@echo "  make dify-logs      - Follow Dify logs"
	@echo "  make dify-ps        - Show Dify container status"
	@echo "  make dify-pull      - Pull latest Dify images"
	@echo ""
	@echo "Backend Code Quality:"
	@echo "  make format         - Format code with ruff"
	@echo "  make check          - Check code with ruff"
	@echo "  make lint           - Format, fix, and lint code (ruff, imports, dotenv)"
	@echo "  make type-check     - Run type checking with basedpyright"
	@echo "  make test           - Run backend unit tests"
	@echo ""
	@echo "Docker Build Targets:"
	@echo "  make build-web      - Build web Docker image"
	@echo "  make build-api      - Build API Docker image"
	@echo "  make build-all      - Build all Docker images"
	@echo "  make push-all       - Push all Docker images"
	@echo "  make build-push-all - Build and push all Docker images"

# Phony targets
.PHONY: build-web build-api push-web push-api build-all push-all build-push-all \
	dev-setup prepare-docker prepare-web prepare-api dev-clean help \
	format check lint type-check test \
	podman-up podman-down podman-restart podman-logs podman-ps \
	run-api run-worker run-web run-all \
	dify-up dify-down dify-restart dify-logs dify-ps dify-pull
