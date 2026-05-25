FROM nginx:1.25-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN rm /etc/nginx/conf.d/default.conf.bak 2>/dev/null || true
EXPOSE 80
