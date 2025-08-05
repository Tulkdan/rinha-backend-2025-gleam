FROM ghcr.io/gleam-lang/gleam:v1.11.1-erlang-alpine

# Set working directory
WORKDIR /app

# Copy source code
COPY . .

# Install dependencies
RUN gleam deps download

# Compile project
RUN gleam build

# Command to run the Gleam application
CMD ["gleam", "run"]
