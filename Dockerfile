FROM dperson/torproxy

USER root

# Crear un usuario no privilegiado
RUN useradd -ms /bin/bash toruser

# Cambiar a usuario no privilegiado
USER toruser

# Copiar configuración personalizada de Tor
COPY torrc /etc/tor/torrc
