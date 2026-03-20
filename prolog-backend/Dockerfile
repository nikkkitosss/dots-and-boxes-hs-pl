FROM node:20-alpine AS proxy-builder

FROM swipl:stable

# Встановити Node.js в той самий контейнер
RUN apt-get update && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY prolog-server.pl .
COPY cors-proxy.js .
COPY start.sh .
RUN chmod +x start.sh

# Prolog на :3002, Node proxy на :3001
EXPOSE 3001
CMD ["./start.sh"]