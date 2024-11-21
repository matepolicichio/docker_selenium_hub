FROM dperson/torproxy

USER root

# Crear un usuario no privilegiado
RUN useradd -ms /bin/bash toruser

# Copiar configuración personalizada sin usar chown
COPY torrc /etc/tor/torrc

# Cambiar a usuario no privilegiado
USER toruser

