FROM debian:bullseye-slim

# Actualizar e instalar Tor y dependencias necesarias
RUN apt-get update && apt-get install -y \
    tor \
    && rm -rf /var/lib/apt/lists/*

# Crear un usuario no privilegiado
RUN useradd -ms /bin/bash toruser

# Crear y configurar directorios requeridos por Tor
RUN mkdir -p /var/run/tor /var/lib/tor /var/log/tor /etc/tor \
    && chown -R toruser:toruser /var/run/tor /var/lib/tor /var/log/tor /etc/tor \
    && chmod 700 /var/run/tor

# Copiar configuración personalizada de Tor
COPY torrc /etc/tor/torrc

# Cambiar a usuario no privilegiado
USER toruser

# Exponer puertos
EXPOSE 9050 9051

# Comando para iniciar Tor
CMD ["tor", "-f", "/etc/tor/torrc"]


