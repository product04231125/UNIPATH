FROM nginx:1.29-alpine
ARG APP_CHANNEL=product
COPY deploy/preview/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/${APP_CHANNEL}/web/ /usr/share/nginx/html/
