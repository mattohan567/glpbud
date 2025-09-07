.PHONY: help dev migrate test deploy-backend deploy-ios clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

dev: ## Start backend and worker locally
	@echo "Starting backend API..."
	uvicorn backend.app.main:app --reload --port 8000 &
	@echo "Starting worker..."
	python backend/worker/main.py &
	@echo "Services running. Press Ctrl+C to stop."
	@wait

migrate: ## Apply database migrations
	@echo "Applying database migrations..."
	psql $$DATABASE_URL < backend/db/001_core.sql
	@echo "Migrations complete."

seed: ## Seed database with demo data
	@echo "Seeding database..."
	python backend/db/seed.py
	@echo "Seed complete."

test: ## Run backend tests
	@echo "Running tests..."
	cd backend && pytest tests/ -v
	@echo "Tests complete."

lint: ## Lint backend code
	@echo "Linting Python code..."
	cd backend && ruff check .
	cd backend && black --check .
	@echo "Linting complete."

format: ## Format backend code
	@echo "Formatting Python code..."
	cd backend && black .
	cd backend && ruff check --fix .
	@echo "Formatting complete."

deploy-backend: ## Deploy backend to Fly.io
	@echo "Deploying backend to Fly.io..."
	flyctl deploy --config ops/fly.toml
	@echo "Backend deployment complete."

build-ios: ## Build iOS app
	@echo "Building iOS app..."
	cd ios && fastlane build
	@echo "iOS build complete."

deploy-ios: ## Deploy iOS to TestFlight
	@echo "Deploying iOS to TestFlight..."
	cd ios && fastlane beta
	@echo "iOS deployment complete."

refresh-mv: ## Refresh materialized views
	@echo "Refreshing materialized views..."
	psql $$DATABASE_URL -c "SELECT refresh_analytics_daily();"
	@echo "Materialized views refreshed."

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	rm -rf backend/.pytest_cache
	rm -rf ios/build
	rm -rf ios/DerivedData
	@echo "Clean complete."

docker-build: ## Build Docker image
	@echo "Building Docker image..."
	docker build -t glp1coach-api:latest -f Dockerfile .
	@echo "Docker build complete."

docker-run: ## Run Docker container
	@echo "Running Docker container..."
	docker run -p 8000:8000 --env-file .env glp1coach-api:latest
	@echo "Container started."