FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf

# Manifest + small assets baked in. Songs are NOT baked — mount them at
# runtime so the image stays small and pushable to Docker Hub:
#   -v /host/path/to/songs:/usr/share/nginx/html/songs:ro
COPY content/manifest.json /usr/share/nginx/html/manifest.json
COPY content/artists/ /usr/share/nginx/html/artists/
COPY content/artwork/ /usr/share/nginx/html/artwork/
COPY content/lyrics/  /usr/share/nginx/html/lyrics/

COPY docker-entrypoint.sh /usr/local/bin/music-entrypoint.sh
RUN chmod +x /usr/local/bin/music-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/music-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
