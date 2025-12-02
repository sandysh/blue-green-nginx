#!/bin/bash
set -e

# -------------------------------
# Configuration
# -------------------------------
APP_NAME="kidsage_web"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"
BLUE_PORT=8000
GREEN_PORT=8001
NGINX_CONF="/etc/nginx/conf.d/kidsage.conf"

# Determine which port is currently live
LIVE_PORT=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$BLUE_PORT && echo $BLUE_PORT || echo $GREEN_PORT)
if [ "$LIVE_PORT" == "$BLUE_PORT" ]; then
  NEW_PORT=$GREEN_PORT
else
  NEW_PORT=$BLUE_PORT
fi

echo "Live port: $LIVE_PORT"
echo "Deploying new container to port: $NEW_PORT"

# -------------------------------
# Build and start new container
# -------------------------------
docker-compose -f $DOCKER_COMPOSE_FILE build web
docker run -d \
  --name ${APP_NAME}_new \
  -p $NEW_PORT:8000 \
  -e DEBUG=0 \
  -e DJANGO_ALLOWED_HOSTS=yourdomain.com \
  -e DATABASE_URL=postgres://postgres:postgres@kidsage_postgres:5432/postgres \
  -e CELERY_BROKER_URL=redis://kidsage_redis:6379/0 \
  ${APP_NAME}_web:latest

# -------------------------------
# Wait for health check
# -------------------------------
echo "Waiting for new container to be healthy..."
until curl -s http://127.0.0.1:$NEW_PORT/health/ > /dev/null; do
  echo "Waiting..."
  sleep 5
done

echo "New container is healthy!"

# -------------------------------
# Update Nginx upstream
# -------------------------------
echo "Switching Nginx to new container..."
sed -i "s/server 127.0.0.1:$LIVE_PORT;/server 127.0.0.1:$NEW_PORT;/" $NGINX_CONF
nginx -s reload

# -------------------------------
# Stop old container
# -------------------------------
OLD_CONTAINER=$(docker ps -q -f "name=${APP_NAME}_web" -f "publish=$LIVE_PORT")
docker stop $OLD_CONTAINER
docker rm $OLD_CONTAINER

echo "Deployment completed successfully! ✅"