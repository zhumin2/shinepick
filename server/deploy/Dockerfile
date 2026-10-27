# 构建阶段
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /bin/api ./cmd/api

# 运行阶段
FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
COPY --from=builder /bin/api /app/api
EXPOSE 8080
ENTRYPOINT ["/app/api"]
