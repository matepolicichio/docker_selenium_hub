FROM dperson/torproxy

USER root

# Cambiar permisos del archivo copiado
COPY torrc /etc/tor/torrc
RUN chmod 644 /etc/tor/torrc

# Crear un usuario no privilegiado
RUN useradd -ms /bin/bash toruser

# Cambiar permisos de directorios necesarios
RUN chown -R toruser:toruser /etc/tor /var/lib/tor /var/log/tor

# Cambiar a usuario no privilegiado
USER toruser
