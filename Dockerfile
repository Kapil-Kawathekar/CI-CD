# Use a lightweight base image
FROM alpine:latest

# Set a working directory
WORKDIR /app

# Default command for the container
CMD ["echo", "Hello, Docker!"]
