################################################################
#
# "TrinityCore+NPCBots latest" docker build
#
################################################################

FROM ubuntu:20.04

# Timezone (must be a valid tzdata value)
ARG tz=Etc/UTC
# Build tools or not
ARG tools=0
# Server build type
ARG buildtype=MinSizeRel

ENV TZ=$tz

EXPOSE 3724
EXPOSE 8085

RUN set -e && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone &&\
 apt-get update &&\
 apt-get install -y git cmake make gcc g++ mysql-server libmysqlclient-dev\
 libreadline-dev libncurses-dev libboost-all-dev libssl-dev libbz2-dev p7zip wget

# Optional data archive containing data folders: dbc, maps [, vmaps, mmaps]
# You have to uncomment 3 (three) rows below to use it without errors:
#  1) ADD ./tc_data.7z /server/bin/tc_data.7z
#  2) mv /root/tc_data.7z . && 7zr x tc_data.7z &&\
#  3) rm -f tc_data* &&\
#
#ADD ./tc_data.7z /root/tc_data.7z

ADD https://github.com/TrinityCore/TrinityCore/releases/download/TDB335.22101/TDB_full_world_335.22101_2022_10_17.7z /server/TDB.7z

WORKDIR /TC
COPY . /TC

RUN pwd && ls -la . &&\
 mkdir -p build && cd build &&\
 cmake ../ -DWITH_COREDEBUG=0 -DTOOLS=$tools -DCMAKE_BUILD_TYPE=$buildtype -DCMAKE_INSTALL_PREFIX=/server &&\
 make -j $(nproc) &&\
 make -j $(nproc) install

RUN service mysql start &&\
 cd /TC/sql/Bots &&\
 bash merge_sqls_auth_unix.sh &&\
 bash merge_sqls_characters_unix.sh &&\
 bash merge_sqls_world_unix.sh &&\
 mv ALL_auth.sql ../updates/auth/3.3.5 &&\
 mv ALL_characters.sql ../updates/characters/3.3.5 &&\
 mv ALL_world.sql ../updates/world/3.3.5 &&\
 cd /TC && mv sql .. && rm -rf * && mv ../sql . &&\
 cd /server/etc &&\
 cp worldserver.conf.dist worldserver.conf && cp authserver.conf.dist authserver.conf

RUN cd /server/bin &&\
 mv ../TDB.7z . && 7zr x TDB.7z && mv TDB_full*.sql TDB.sql &&\
# mv /root/tc_data.7z . && 7zr x tc_data.7z &&\
 #mysql -uroot < /TC/sql/create/create_mysql.sql &&\
 #mysql -utrinity -ptrinity auth < /TC/sql/base/auth_database.sql &&\
 #mysql -utrinity -ptrinity characters < /TC/sql/base/characters_database.sql &&\
 #mysql -utrinity -ptrinity world < TDB.sql &&\
 #rm -f TDB* &&\
 rm -rf /TC/* &&\
# rm -f tc_data* &&\
 apt-get remove -y git cmake make gcc g++ p7zip wget &&\
 apt-get -y autoremove && apt-get clean &&\
 ./authserver --version && ./worldserver --version
