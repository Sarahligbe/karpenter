FROM golang:1.22.5-alpine AS build

WORKDIR /bird

COPY go.mod ./

RUN go mod download

COPY *.go ./

RUN go build -o getBird

FROM alpine:3.20

WORKDIR /bird

# Copy binary from build stage
COPY --from=build /bird/getBird .

# Create non-root user and change ownership of the binary
RUN addgroup -S birdgroup && adduser -S birduser -G birdgroup is && chown birduser:birdgroup getBird

USER birduser

EXPOSE 4201

ENTRYPOINT ["./getBird"]