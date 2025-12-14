# Multi-stage Docker build for LockWise Backend
# Stage 1: Build Rust application
FROM rust:1.91-trixie AS rust-builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

# Stage 2: Setup Python environment and final image
FROM python:3.10-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
	ffmpeg \
	libpq-dev \
	libsndfile1 \
	libsox-fmt-all \
	pkg-config \
	sox \
	&& rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Python requirements and install dependencies
COPY requirements.txt constraints.txt .

RUN pip install --no-cache-dir \
	-r requirements.txt \
	-c constraints.txt \
	--extra-index-url https://download.pytorch.org/whl/cpu

# Copy built Rust binary
COPY --from=rust-builder /app/target/release/backend ./backend

# Copy Python service
COPY speechbrain_service.py .

# Create models directory for SpeechBrain
RUN mkdir -p models/spkrec

# Declare volume for model persistence across container restarts
VOLUME ["/app/models"]

# Expose only the main backend port (12223)
EXPOSE 12223

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
	CMD curl -f http://localhost:12223/health || exit 1

# Start both services
CMD ["sh", "-c", "uvicorn speechbrain_service:app --host 0.0.0.0 --port 5008 --workers 1 & ./backend"]
