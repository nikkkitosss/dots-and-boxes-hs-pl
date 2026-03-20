FROM haskell:9.6-slim

WORKDIR /app

# Спочатку встановлюємо залежності (кешується)
RUN cabal update && \
    cabal install --lib \
      scotty \
      aeson \
      wai \
      wai-extra \
      http-types \
      containers \
      text

COPY Server.hs .

EXPOSE 3000
CMD ["runghc", "Server.hs"]