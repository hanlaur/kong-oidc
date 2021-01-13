#
# This Dockerfile is modified version of Revomatico Dockerfile:
# https://github.com/revomatico/docker-kong-oidc/blob/master/Dockerfile
# revomatico/docker-kong-oidc is licensed under the Apache License 2.0
#
# - In-repository Dockerfile
# - Honors kong-plugin-session version bundled with Kong
# - Honors lua-resty-openidc version specified by plugin
# - Removes unneeded build dependencies
# - Removes modifying /usr/local/kong permission (not needed anymore for current Kong?)
# - Uses "kong" instead of "kong/kong" for base image
# - Runs apk upgrade

#
# Build arguments. KONG_OIDC_VER must match the rockspc.
#
ARG KONG_VER="2.2.1"
ARG KONG_OIDC_VER="1.2.1.hl1-1"

ARG KONG_BASE_IMAGE="kong:${KONG_VER}-alpine"
ARG LUA_BASE_DIR="/usr/local/share/lua/5.1"
ARG NGX_DISTRIBUTED_SHM_VER="1.0.2"

#
# Build rock file
#
FROM ${KONG_BASE_IMAGE} AS builder
ARG LUA_BASE_DIR
ARG KONG_OIDC_VER
USER root
RUN mkdir /build
WORKDIR /build
COPY kong kong/
COPY kong-oidc-${KONG_OIDC_VER}.rockspec .
RUN luarocks make --pack-binary-rock

#
# Build kong image
#
FROM ${KONG_BASE_IMAGE}

USER root

LABEL authors="Rami Abusereya <rami.abusereya@revomatico.com>,Cristian Chiru <cristian.chiru@revomatico.com>"

ARG LUA_BASE_DIR
ARG KONG_OIDC_VER
ARG NGX_DISTRIBUTED_SHM_VER

RUN apk update && apk upgrade && rm -rf /var/cache/apk/*

COPY --from=builder /build/kong-oidc-${KONG_OIDC_VER}.all.rock /

RUN set -ex \
  && apk --no-cache add --virtual .build-dependencies \
    curl \
  \
## Install plugins
 # Download ngx-distributed-shm dshm library
    && curl -sL https://raw.githubusercontent.com/grrolland/ngx-distributed-shm/${NGX_DISTRIBUTED_SHM_VER}/lua/dshm.lua > ${LUA_BASE_DIR}/resty/dshm.lua \
 # Install kong-oidc
    && luarocks install /kong-oidc-${KONG_OIDC_VER}.all.rock \
 # Patch nginx_kong.lua for kong-oidc session_secret
    && TPL=${LUA_BASE_DIR}/kong/templates/nginx_kong.lua \
    && cp ${TPL} ${TPL}.original \
    # May cause side effects when using another nginx under this kong, unless set to the same value
    && sed -i "/server_name kong;/a\ \n\
set_decode_base64 \$session_secret \${{X_SESSION_SECRET}};\n" "$TPL" \
 # Patch nginx_kong.lua to set dictionaries
    && sed -i -E '/^lua_shared_dict kong\s+.+$/i\ \n\
variables_hash_max_size 2048;\n\
lua_shared_dict discovery \${{X_OIDC_CACHE_DISCOVERY_SIZE}};\n\
lua_shared_dict jwks \${{X_OIDC_CACHE_JWKS_SIZE}};\n\
lua_shared_dict introspection \${{X_OIDC_CACHE_INTROSPECTION_SIZE}};\n\
> if x_session_storage == "shm" then\n\
lua_shared_dict \${{X_SESSION_SHM_STORE}} \${{X_SESSION_SHM_STORE_SIZE}};\n\
> end\n\
' "$TPL" \
 # Patch nginx_kong.lua to add for memcached sessions
    && sed -i "/server_name kong;/a\ \n\
    ## Session:
    set \$session_storage \${{X_SESSION_STORAGE}};\n\
    set \$session_name \${{X_SESSION_NAME}};\n\
    ## Session: Memcached specific
    set \$session_memcache_connect_timeout \${{X_SESSION_MEMCACHE_CONNECT_TIMEOUT}};\n\
    set \$session_memcache_send_timeout \${{X_SESSION_MEMCACHE_SEND_TIMEOUT}};\n\
    set \$session_memcache_read_timeout \${{X_SESSION_MEMCACHE_READ_TIMEOUT}};\n\
    set \$session_memcache_prefix \${{X_SESSION_MEMCACHE_PREFIX}};\n\
    set \$session_memcache_host \${{X_SESSION_MEMCACHE_HOST}};\n\
    set \$session_memcache_port \${{X_SESSION_MEMCACHE_PORT}};\n\
    set \$session_memcache_uselocking \${{X_SESSION_MEMCACHE_USELOCKING}};\n\
    set \$session_memcache_spinlockwait \${{X_SESSION_MEMCACHE_SPINLOCKWAIT}};\n\
    set \$session_memcache_maxlockwait \${{X_SESSION_MEMCACHE_MAXLOCKWAIT}};\n\
    set \$session_memcache_pool_timeout \${{X_SESSION_MEMCACHE_POOL_TIMEOUT}};\n\
    set \$session_memcache_pool_size \${{X_SESSION_MEMCACHE_POOL_SIZE}};\n\
    ## Session: DHSM specific
    set \$session_dshm_region \${{X_SESSION_DSHM_REGION}};\n\
    set \$session_dshm_connect_timeout \${{X_SESSION_DSHM_CONNECT_TIMEOUT}};\n\
    set \$session_dshm_send_timeout \${{X_SESSION_DSHM_SEND_TIMEOUT}};\n\
    set \$session_dshm_read_timeout \${{X_SESSION_DSHM_READ_TIMEOUT}};\n\
    set \$session_dshm_host \${{X_SESSION_DSHM_HOST}};\n\
    set \$session_dshm_port \${{X_SESSION_DSHM_PORT}};\n\
    set \$session_dshm_pool_name \${{X_SESSION_DSHM_POOL_NAME}};\n\
    set \$session_dshm_pool_timeout \${{X_SESSION_DSHM_POOL_TIMEOUT}};\n\
    set \$session_dshm_pool_size \${{X_SESSION_DSHM_POOL_SIZE}};\n\
    set \$session_dshm_pool_backlog \${{X_SESSION_DSHM_POOL_BACKLOG}};\n\
    ## Session: SHM Specific
    set \$session_shm_store \${{X_SESSION_SHM_STORE}};\n\
    set \$session_shm_uselocking \${{X_SESSION_SHM_USELOCKING}};\n\
    set \$session_shm_lock_exptime \${{X_SESSION_SHM_LOCK_EXPTIME}};\n\
    set \$session_shm_lock_timeout \${{X_SESSION_SHM_LOCK_TIMEOUT}};\n\
    set \$session_shm_lock_step \${{X_SESSION_SHM_LOCK_STEP}};\n\
    set \$session_shm_lock_ratio \${{X_SESSION_SHM_LOCK_RATIO}};\n\
    set \$session_shm_lock_max_step \${{X_SESSION_SHM_LOCK_MAX_STEP}};\n\
" "$TPL" \
 # Patch kong_defaults.lua to add custom variables that are replaced dynamically in the template above when kong is started
    && TPL=${LUA_BASE_DIR}/kong/templates/kong_defaults.lua \
    && cp ${TPL} ${TPL}.original \
    && sed -i "/\]\]/i\ \n\
x_session_storage = cookie\n\
x_session_name = oidc_session\n\
x_session_secret = ''\n\
\n\
x_session_memcache_prefix = oidc_sessions\n\
x_session_memcache_connect_timeout = '1000'\n\
x_session_memcache_send_timeout = '1000'\n\
x_session_memcache_read_timeout = '1000'\n\
x_session_memcache_host = memcached\n\
x_session_memcache_port = '11211'\n\
x_session_memcache_uselocking = 'off'\n\
x_session_memcache_spinlockwait = '150'\n\
x_session_memcache_maxlockwait = '30'\n\
x_session_memcache_pool_timeout = '1000'\n\
x_session_memcache_pool_size = '10'\n\
\n\
x_session_dshm_region = oidc_sessions\n\
x_session_dshm_connect_timeout = '1000'\n\
x_session_dshm_send_timeout = '1000'\n\
x_session_dshm_read_timeout = '1000'\n\
x_session_dshm_host = hazelcast\n\
x_session_dshm_port = '4321'\n\
x_session_dshm_pool_name = oidc_sessions\n\
x_session_dshm_pool_timeout = '1000'\n\
x_session_dshm_pool_size = '10'\n\
x_session_dshm_pool_backlog = '10'\n\
\n\
x_session_shm_store_size = 5m\n\
x_session_shm_store = oidc_sessions\n\
x_session_shm_uselocking = off\n\
x_session_shm_lock_exptime = '30'\n\
x_session_shm_lock_timeout = '5'\n\
x_session_shm_lock_step = '0.001'\n\
x_session_shm_lock_ratio = '2'\n\
x_session_shm_lock_max_step = '0.5'\n\
\n\
x_oidc_cache_discovery_size = 128k\n\
x_oidc_cache_jwks_size = 128k\n\
x_oidc_cache_introspection_size = 128k\n\
\n\
" "$TPL" \
    && apk del .build-dependencies 2>/dev/null \
    # Allow regular users to run these programs and bind to ports < 1024
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/kong \
    && setcap 'cap_net_bind_service=+ep' /usr/local/openresty/nginx/sbin/nginx
RUN rm -f /kong-oidc-${KONG_OIDC_VER}.all.rock

USER kong
