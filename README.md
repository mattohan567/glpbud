# GLP-1 Coach

iOS-first, Claude-powered weight management app with agentic orchestration and production observability.

## Architecture

- **iOS App**: SwiftUI + MVVM with offline-first design and optimistic UI
- **Backend**: FastAPI thin control plane with event-driven architecture
- **AI**: Claude tool orchestration with Haiku/Sonnet escalation
- **Database**: Supabase (Postgres + Auth + Storage)
- **Observability**: Langfuse (LLM traces), Sentry, OpenTelemetry
- **Deployment**: Fly.io (API + Worker), TestFlight (iOS)

## Features

- 📸 **AI Food Logging**: Photo and text parsing with Claude Vision
- 💊 **GLP-1 Tracking**: Medication schedules and adherence
- 📊 **Trends & Analytics**: Weight, macros, and calorie tracking
- 🤖 **AI Coach**: Safety-checked coaching with medical disclaimers
- 🔄 **Offline Sync**: Local-first with background sync
- 🔍 **Full Observability**: LLM traces, costs, and performance metrics

## Quick Start

### Prerequisites

- Python 3.11+
- Node.js 18+
- Xcode 15+
- Supabase account
- Anthropic API key

### Backend Setup

```bash
# Install dependencies
cd backend
pip install -r requirements.txt

# Set environment variables
cp .env.example .env
# Edit .env with your keys

# Run migrations
make migrate

# Seed database
make seed

# Start development servers
make dev
```

### iOS Setup

```bash
# Install dependencies
cd ios
bundle install

# Open in Xcode
open GLP1Coach.xcodeproj

# Set API_BASE in scheme environment variables
# Build and run (Cmd+R)
```

### Running Tests

```bash
# Backend tests
make test

# iOS tests
cd ios && fastlane test
```

## Deployment

### Backend Deployment (Fly.io)

```bash
# First time setup
flyctl launch --config ops/fly.toml

# Deploy
make deploy-backend
```

### iOS Deployment (TestFlight)

```bash
# Setup certificates (first time)
cd ios && fastlane match

# Deploy to TestFlight
make deploy-ios
```

## API Endpoints

- `POST /parse/meal-image` - Parse meal photo
- `POST /parse/meal-text` - Parse meal text
- `POST /log/{meal|exercise|weight|med}` - Log entries
- `GET /today` - Today's stats
- `GET /trends?range=7d|30d|90d` - Historical trends
- `POST /coach/ask` - AI coaching
- `GET /med/next` - Next medication dose

## Environment Variables

See `.env.example` for required configuration:

- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_KEY` - Supabase anon key
- `ANTHROPIC_API_KEY` - Claude API key
- `LANGFUSE_PUBLIC_KEY` - Langfuse public key
- `SENTRY_DSN` - Sentry error tracking

## Monitoring

### Langfuse Dashboard
- View all Claude API calls
- Track costs and latencies
- Debug low-confidence parses

### Sentry
- Backend and iOS crash reporting
- Performance monitoring

### Metrics
- Daily active users
- Logs per day
- Confidence scores
- GLP-1 adherence rates

## Development

### Local Development

```bash
# Start all services
make dev

# Run linting
make lint

# Format code
make format

# Refresh materialized views
make refresh-mv
```

### Docker

```bash
# Build image
make docker-build

# Run container
make docker-run
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT

## Support

For issues and questions, please open a GitHub issue.