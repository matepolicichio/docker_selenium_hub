FROM dperson/torproxy

USER root

# Crear un usuario no privilegiado
RUN useradd -ms /bin/bash toruser

# Cambiar permisos de los directorios necesarios
RUN chown -R toruser:toruser /etc/tor /var/lib/tor /var/log/tor

# Copiar configuración personalizada de Tor
COPY torrc /etc/tor/torrc

# Asegurar permisos del archivo torrc
RUN chmod 644 /etc/tor/torrc

# Cambiar a usuario no privilegiado
USER toruser

