FROM node:24-alpine
WORKDIR /app
COPY package.json server.js ./
ENV APP_VERSION=1.0
USER node
EXPOSE 3000
CMD ["node", "server.js"]
