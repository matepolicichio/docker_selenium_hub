FROM dperson/torproxy

USER root

# Cambiar permisos de los directorios necesarios
RUN chown -R toruser:toruser /etc/tor /var/lib/tor /var/log/tor

# Crear un usuario no privilegiado
RUN useradd -ms /bin/bash toruser

# Cambiar a usuario no privilegiado
USER toruser

# Copiar configuración personalizada de Tor
COPY torrc /etc/tor/torrc