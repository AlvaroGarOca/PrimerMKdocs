# FROM python:3.12-alpine
# WORKDIR /app
# COPY . /app
# RUN pip install -r requirements.txt
# EXPOSE 8080
# CMD [ "mkdocs", "serve", "--dev-addr=0.0.0.0:8080"]

FROM python:3.12-alpine AS builder
WORKDIR /app
COPY . /app
RUN pip install -r requirements.txt
RUN mkdocs build

FROM nginx:1.27.4-alpine
COPY --from=builder /app/site /usr/share/nginx/html/