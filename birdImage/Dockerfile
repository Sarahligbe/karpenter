FROM golang:1.22.5-alpine AS build

WORKDIR /birdImage

COPY go.mod ./

RUN go mod download

COPY *.go ./

RUN go build -o getBirdImage

FROM alpine:3.20

WORKDIR /birdImage

# Copy binary from build stage
COPY --from=build /birdImage/getBirdImage .

# Create non-root user and change ownership of the binary
RUN addgroup -S birdgroup && adduser -S birduser -G birdgroup is && chown birduser:birdgroup getBirdImage

USER birduser

EXPOSE 4200

ENTRYPOINT ["./getBirdImage"]