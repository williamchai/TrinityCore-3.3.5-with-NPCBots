# MIT License
# Copyright (c) 2017-2022 Nicola Worthington <nicolaw@tfb.net>
# https://gitlab.com/nicolaw/trinitycore/

FROM debian:12 AS build

RUN mkdir -pv /build/ /artifacts/ /src/

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -qq -o Dpkg::Use-Pty=0 update \
 && apt-get -qq -o Dpkg::Use-Pty=0 install --no-install-recommends -y \
    binutils \
    ca-certificates \
    clang \
    cmake \
    curl \
    default-libmysqlclient-dev \
    default-mysql-client \
    g++-11 \
    git \
    jq \
    libboost-all-dev \
    libbz2-dev \
    libmariadb-dev \
    libncurses-dev \
    libreadline-dev \
    libssl-dev \
    make \
    patch \
    p7zip \
    xml2 \
    zlib1g-dev \
 < /dev/null > /dev/null \
 && rm -rf /var/lib/apt/lists/* \
 && update-alternatives --install /usr/bin/cc cc /usr/bin/clang 100 \
 && update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang 100

# ARG TC_GIT_BRANCH=3.3.5
# ARG TC_GIT_REPO=https://github.com/williamchai/TrinityCore-3.3.5-with-NPCBots
# RUN git clone --single-branch --depth 1 "${TC_GIT_REPO}" /src
COPY cmake /src/cmake
COPY contrib /src/contrib
COPY dep /src/dep
COPY sql /src/sql
COPY src /src/src
COPY sql /src/sql
COPY .git /src/.git
COPY CMakeLists.txt PreLoad.cmake revision_data.h.in.cmake AUTHORS COPYING /src/

RUN mkdir /artifacts/src/

WORKDIR /build

# https://trinitycore.info/en/install/Core-Installation/linux-core-installation
ARG INSTALL_PREFIX=/opt/trinitycore
ARG CONF_DIR=/etc
RUN cmake ../src -DTOOLS=1 -DWITH_WARNINGS=0 -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" -DCONF_DIR="${CONF_DIR}" -Wno-dev \
 && make -j $(nproc) \
 && make install

WORKDIR /artifacts

# Install some additional utilitiy helper tools and reference material.
#COPY ["gettdb","getsql","genmapdata","wait-for-mysql.sh","./${INSTALL_PREFIX}/bin/"]
#COPY ["docker-compose.yaml","aws/trinitycore-cfn.yaml","./${INSTALL_PREFIX}/"]
#COPY ["LICENSE","*.md","./"]
ADD https://raw.githubusercontent.com/neechbear/tcadmin/master/tcadmin "./${INSTALL_PREFIX}/bin/tcadmin"
RUN mkdir -pv usr/bin/ && ln -s -t usr/bin/ /bin/env && chmod -v 0755 "./${INSTALL_PREFIX}/bin/"*
RUN mkdir -pv usr/share/git-core/templates/branches/ usr/share/git-core/templates/info/ usr/share/git-core/templates/

# Save upstream source Git SHA information that we built form.
ARG TDB_FULL_URL
RUN git -C /src rev-parse HEAD > .git-rev \
 && git -C /src rev-parse --short HEAD > .git-rev-short \
 && echo "$TDB_FULL_URL" > .tdb-full-url

# Copy binaries and example .dist.conf configuration files.
RUN tar -cf - \
    "${INSTALL_PREFIX}" \
    /bin/bash \
    /etc/ca-certificates* \
    /etc/*server.conf.dist \
    /etc/ssl/certs \
    /src/AUTHORS \
    /src/COPYING \
    /usr/bin/7zr \
    /usr/bin/curl \
    /usr/bin/git \
    /usr/bin/jq \
    /usr/bin/mariadb \
    /usr/bin/mysql \
    /usr/bin/stdbuf \
    /usr/bin/xml2 \
    /usr/lib/git-core/git-remote-http* \
    /usr/lib/p7zip/7zr \
    /usr/libexec/coreutils/libstdbuf.so \
    /usr/share/ca-certificates \
  | tar -C /artifacts/ -xvf -

# Copy linked libraries and strip symbols from binaries.
RUN ldd opt/trinitycore/bin/* usr/bin/* usr/lib/git-core/* | grep ' => ' | tr -s '[:blank:]' '\n' | grep '^/' | sort -u | \
    xargs -I % sh -c 'mkdir -pv $(dirname .%); cp -v % .%'
RUN strip \
    "./${INSTALL_PREFIX}/bin/"*server \
    "./${INSTALL_PREFIX}/bin/"*extractor \
    "./${INSTALL_PREFIX}/bin/"*generator \
    "./${INSTALL_PREFIX}/bin/"*assembler

# Copy example .conf.dist configuration files into expected .conf locations.
RUN cp -v etc/authserver.conf.dist etc/authserver.conf \
 && cp -v etc/worldserver.conf.dist etc/worldserver.conf \
 && find etc/ -name '*server.conf' -exec sed -i"" -r \
    -e 's,^(.*DatabaseInfo[[:space:]]*=[[:space:]]*")[[:alnum:]\.-]*(;.*"),\1mysql\2,' \
    -e 's,^(LogsDir[[:space:]]*=[[:space:]]).*,\1"/logs",' \
    -e 's,^(SourceDirectory[[:space:]]*=[[:space:]]).*,\1"/src",' \
    -e 's,^(MySQLExecutable[[:space:]]*=[[:space:]]).*,\1"/usr/bin/mysql",' \
    '{}' \; \
 && sed -i"" -r \
    -e 's,^(DataDir[[:space:]]*=[[:space:]]).*,\1"/mapdata",' \
    -e 's,^(Console\.Enable[[:space:]]*=[[:space:]]).*,\10,' \
    etc/worldserver.conf \
 && mkdir -pv "./${INSTALL_PREFIX}/etc/" \
 && ln -s -T /etc/worldserver.conf      "./${INSTALL_PREFIX}/etc/worldserver.conf" \
 && ln -s -T /etc/worldserver.conf.dist "./${INSTALL_PREFIX}/etc/worldserver.conf.dist" \
 && ln -s -T /etc/authserver.conf       "./${INSTALL_PREFIX}/etc/authserver.conf" \
 && ln -s -T /etc/authserver.conf.dist  "./${INSTALL_PREFIX}/etc/authserver.conf.dist"

# Copy SQL source files. (Exclude old/ and updates/ on a "slim" image).
ARG WITH_SQL=
RUN tar -cf - $([ -n "${WITH_SQL}" ] || echo --exclude=/src/sql/old/* --exclude=/src/sql/updates/*) /src/sql | tar -C /artifacts/ -xvf - | tail

# Optionally download TDB_full_world SQL dump to populate worldserver database.
WORKDIR /artifacts/src/sql
RUN [ -z "${WITH_SQL}" ] && exit 0 ; \
 (TC_CHROOT="/artifacts" "../../${INSTALL_PREFIX}/bin/gettdb" || "../../${INSTALL_PREFIX}/bin/gettdb" "${TC_GIT_BRANCH}") \
 && rm -fv *.7z

# Convenience symlinks.
WORKDIR /artifacts
RUN if ls src/sql/TDB_full_world_*.sql >/dev/null 2>&1 ; then ln -s src/sql/TDB_full_world_*.sql ; fi
RUN ln -s src/sql/
RUN ln -s -T /src/sql/ "./${INSTALL_PREFIX}/sql"
RUN ln -s -T /src/ "./${INSTALL_PREFIX}/src"


FROM busybox:1.35.0-glibc

ARG INSTALL_PREFIX=/opt/trinitycore
ENV LD_LIBRARY_PATH=/lib:/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:${INSTALL_PREFIX}/lib \
    PATH=/bin:/usr/bin:${INSTALL_PREFIX}/bin

# Copy built software artifcts into final image.
COPY --from=build /artifacts /
COPY --from=nicolaw/tcpasswd:latest /tcpasswd "${INSTALL_PREFIX}/bin/tcpasswd"

# Set suitible unprivileged user, home directory and initial working diretory.
ARG TRINITY_UID=1000
ARG TRINITY_GID=1000
RUN addgroup -g "${TRINITY_GID}" trinity \
 && adduser -G trinity -D -u "${TRINITY_UID}" -h "${INSTALL_PREFIX}" trinity
USER trinity
WORKDIR /

# Add documentation labels.
ARG TC_GIT_BRANCH=3.3.5
ARG VARIANT=slim
ARG BUILD_DATE
ARG VCS_REF
ARG BUILD_VERSION
ARG TDB_FULL_URL
ARG LABEL_IMAGE_SUFFIX

LABEL org.opencontainers.image.authors="Nicola Worthington <nicolaw@tfb.net>" \
      org.opencontainers.image.created="$BUILD_DATE" \
      org.opencontainers.image.revision="$VCS_REF" \
      org.opencontainers.image.version="$BUILD_VERSION" \
      org.opencontainers.image.licenses="MIT GPL-2.0"
